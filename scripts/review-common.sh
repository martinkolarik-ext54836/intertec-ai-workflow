#!/usr/bin/env bash

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$(cd "$AI_ROOT/.." && pwd)}"
RUNTIME_ROOT="${REVIEW_RUNTIME_ROOT:-$HOME/Library/Application Support/IntertecAIReviewer}"
LOG_ROOT="${REVIEW_LOG_ROOT:-$HOME/Library/Logs/IntertecAIReviewer}"
REVIEW_MODEL="${REVIEW_MODEL:-gpt-5.6-terra}"
REVIEW_REASONING="${REVIEW_REASONING:-high}"
REVIEW_MAX_ATTEMPTS="${REVIEW_MAX_ATTEMPTS:-3}"
REVIEW_ENV_COOLDOWN_STEPS="${REVIEW_ENV_COOLDOWN_STEPS:-60 300 900 3600}"
REVIEW_RETENTION_DAYS="${REVIEW_RETENTION_DAYS:-30}"
REVIEW_LOG_MAX_BYTES="${REVIEW_LOG_MAX_BYTES:-1048576}"
REVIEW_LOG_KEEP="${REVIEW_LOG_KEEP:-3}"

sanitize_count() {
  local value="$1"
  local fallback="$2"
  case "$value" in
    ''|*[!0-9]*) printf '%s\n' "$fallback" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

# Zero attempts is a valid choice: give up after the first failure.
REVIEW_MAX_ATTEMPTS="$(sanitize_count "$REVIEW_MAX_ATTEMPTS" 3)"
REVIEW_RETENTION_DAYS="$(sanitize_count "$REVIEW_RETENTION_DAYS" 30)"
REVIEW_LOG_MAX_BYTES="$(sanitize_count "$REVIEW_LOG_MAX_BYTES" 1048576)"
REVIEW_LOG_KEEP="$(sanitize_count "$REVIEW_LOG_KEEP" 3)"
if [ "$REVIEW_LOG_KEEP" -lt 1 ]; then
  REVIEW_LOG_KEEP=1
fi

mkdir -p "$RUNTIME_ROOT/locks" "$RUNTIME_ROOT/completed" \
  "$RUNTIME_ROOT/failures" "$RUNTIME_ROOT/results" \
  "$RUNTIME_ROOT/worktrees" "$LOG_ROOT"

ENVIRONMENT_COOLDOWN_FILE="$RUNTIME_ROOT/environment-cooldown"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_review() {
  printf '%s %s\n' "$(timestamp)" "$*" | tee -a "$LOG_ROOT/reviewer.log"
}

# A process identity that survives PID reuse: the PID plus its start time.
process_start_token() {
  local pid="$1"
  local started
  started="$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s '[:space:]' ' ')"
  started="${started# }"
  started="${started% }"
  [ -n "$started" ] || return 1
  printf '%s\n' "$started"
}

lock_is_stale() {
  local lock_dir="$1"
  local owner stored_pid stored_started current_started
  [ -f "$lock_dir/owner" ] || return 0
  owner="$(cat "$lock_dir/owner" 2>/dev/null || true)"
  stored_pid="${owner%%|*}"
  stored_started="${owner#*|}"
  case "$stored_pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  kill -0 "$stored_pid" 2>/dev/null || return 0
  if [ -n "$stored_started" ]; then
    current_started="$(process_start_token "$stored_pid" 2>/dev/null || true)"
    if [ -n "$current_started" ] && [ "$current_started" != "$stored_started" ]; then
      return 0
    fi
  fi
  return 1
}

claim_lock() {
  local lock_dir="$1"
  mkdir "$lock_dir" 2>/dev/null || return 1
  printf '%s|%s\n' "$$" "$(process_start_token "$$" 2>/dev/null || true)" \
    > "$lock_dir/owner"
}

# Never report success unless this process actually created the lock directory.
acquire_lock() {
  local lock_dir="$1"
  if claim_lock "$lock_dir"; then
    return 0
  fi
  if ! lock_is_stale "$lock_dir"; then
    return 1
  fi
  rm -rf "$lock_dir" 2>/dev/null || true
  claim_lock "$lock_dir"
}

now_epoch() {
  date '+%s'
}

# Environment failures (no Codex, no login) are not the reviewed commit's fault.
# They pause every repository for a growing interval instead of consuming the
# per-commit attempt budget.
environment_cooldown_remaining() {
  local until now remaining
  if [ ! -f "$ENVIRONMENT_COOLDOWN_FILE" ]; then
    printf '0\n'
    return 0
  fi
  until="$(awk -F= '$1 == "until" { print $2; exit }' "$ENVIRONMENT_COOLDOWN_FILE" 2>/dev/null || true)"
  until="$(sanitize_count "$until" 0)"
  now="$(now_epoch)"
  remaining=$((until - now))
  if [ "$remaining" -lt 0 ]; then
    remaining=0
  fi
  printf '%s\n' "$remaining"
}

# Prints "<failures> <delay_seconds>".
record_environment_failure() {
  local reason="$1"
  local failures delay step index
  failures=0
  if [ -f "$ENVIRONMENT_COOLDOWN_FILE" ]; then
    failures="$(awk -F= '$1 == "failures" { print $2; exit }' "$ENVIRONMENT_COOLDOWN_FILE" 2>/dev/null || true)"
  fi
  failures="$(sanitize_count "$failures" 0)"
  failures=$((failures + 1))
  index=0
  delay=60
  for step in $REVIEW_ENV_COOLDOWN_STEPS; do
    index=$((index + 1))
    delay="$(sanitize_count "$step" 60)"
    if [ "$index" -ge "$failures" ]; then
      break
    fi
  done
  {
    printf 'failures=%s\n' "$failures"
    printf 'until=%s\n' "$(( $(now_epoch) + delay ))"
    printf 'delay=%s\n' "$delay"
    printf 'reason=%s\n' "$reason"
    printf 'since=%s\n' "$(timestamp)"
  } > "$ENVIRONMENT_COOLDOWN_FILE"
  printf '%s %s\n' "$failures" "$delay"
}

clear_environment_failure() {
  rm -f "$ENVIRONMENT_COOLDOWN_FILE" 2>/dev/null || true
  return 0
}

rotate_log_file() {
  local file="$1"
  local size index
  [ -f "$file" ] || return 0
  size="$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')"
  size="$(sanitize_count "$size" 0)"
  [ "$size" -ge "$REVIEW_LOG_MAX_BYTES" ] || return 0
  index="$REVIEW_LOG_KEEP"
  rm -f "$file.$index"
  while [ "$index" -gt 1 ]; do
    if [ -f "$file.$((index - 1))" ]; then
      mv "$file.$((index - 1))" "$file.$index"
    fi
    index=$((index - 1))
  done
  mv "$file" "$file.1"
}

rotate_logs() {
  [ "$REVIEW_LOG_MAX_BYTES" -gt 0 ] || return 0
  rotate_log_file "$LOG_ROOT/reviewer.log"
  rotate_log_file "$LOG_ROOT/codex.log"
}

# The runtime directory is a disposable cache. Every durable record already
# lives in the owning repository's Git history.
prune_runtime() {
  local directory lock
  for lock in "$RUNTIME_ROOT"/locks/*; do
    [ -d "$lock" ] || continue
    if lock_is_stale "$lock"; then
      rm -rf "$lock" 2>/dev/null || true
    fi
  done
  [ "$REVIEW_RETENTION_DAYS" -gt 0 ] || return 0
  for directory in completed failures results; do
    [ -d "$RUNTIME_ROOT/$directory" ] || continue
    find "$RUNTIME_ROOT/$directory" -maxdepth 1 -type f \
      -mtime "+$REVIEW_RETENTION_DAYS" -delete 2>/dev/null || true
  done
  find "$LOG_ROOT" -maxdepth 1 -type f -name '*.log.[0-9]*' \
    -mtime "+$REVIEW_RETENTION_DAYS" -delete 2>/dev/null || true
  return 0
}

normalize_key() {
  printf '%s' "$1" | tr '[:upper:] -' '[:lower:]__'
}

state_value() {
  local file="$1"
  local wanted
  wanted="$(normalize_key "$2")"
  awk -v wanted="$wanted" '
    index($0, ":") {
      key = substr($0, 1, index($0, ":") - 1)
      value = substr($0, index($0, ":") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/[ -]/, "_", key)
      key = tolower(key)
      if (key == wanted) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^`|`$/, "", value)
        print value
        exit
      }
    }
  ' "$file"
}

state_set() {
  local file="$1"
  local requested_key="$2"
  local value="$3"
  local wanted temporary
  wanted="$(normalize_key "$requested_key")"
  temporary="$(mktemp "$RUNTIME_ROOT/state.XXXXXX")"
  awk -v wanted="$wanted" -v requested_key="$requested_key" -v value="$value" '
    BEGIN { replaced = 0 }
    index($0, ":") {
      key = substr($0, 1, index($0, ":") - 1)
      normalized = key
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", normalized)
      gsub(/[ -]/, "_", normalized)
      normalized = tolower(normalized)
      if (normalized == wanted) {
        print requested_key ": " value
        replaced = 1
        next
      }
    }
    { print }
    END {
      if (!replaced) print requested_key ": " value
    }
  ' "$file" > "$temporary"
  mv "$temporary" "$file"
}

safe_project_path() {
  local value="$1"
  value="${value#\`}"; value="${value%\`}"
  case "$value" in
    .ai/*) ;;
    *) return 1 ;;
  esac
  case "/$value/" in
    */../*|*/./*) return 1 ;;
  esac
  printf '%s\n' "$value"
}

state_value_any() {
  local file="$1"
  shift
  local key value
  for key in "$@"; do
    value="$(state_value "$file" "$key")"
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

repo_id() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print substr($1, 1, 16)}'
  else
    printf '%s' "$1" | sha256sum | awk '{print substr($1, 1, 16)}'
  fi
}

find_codex() {
  if [ -n "${CODEX_BIN:-}" ] && [ -x "$CODEX_BIN" ]; then
    printf '%s\n' "$CODEX_BIN"
    return 0
  fi
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi
  local candidate
  candidate="$(find "$HOME/.vscode/extensions" -type f -path '*/openai.chatgpt-*/bin/*/codex' -perm -111 2>/dev/null | sort | tail -n 1)"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

notify_review() {
  [ "${REVIEW_NOTIFY:-1}" = "1" ] || return 0
  [ -x /usr/bin/osascript ] || return 0
  /usr/bin/osascript -e "display notification \"$2\" with title \"AI review: $1\"" >/dev/null 2>&1 || true
}
