#!/usr/bin/env bash

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$(cd "$AI_ROOT/.." && pwd)}"
RUNTIME_ROOT="${REVIEW_RUNTIME_ROOT:-$HOME/Library/Application Support/IntertecAIReviewer}"
LOG_ROOT="${REVIEW_LOG_ROOT:-$HOME/Library/Logs/IntertecAIReviewer}"
REVIEW_MODEL="${REVIEW_MODEL:-gpt-5.6-terra}"
REVIEW_REASONING="${REVIEW_REASONING:-high}"

mkdir -p "$RUNTIME_ROOT/locks" "$RUNTIME_ROOT/completed" \
  "$RUNTIME_ROOT/results" "$RUNTIME_ROOT/worktrees" "$LOG_ROOT"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_review() {
  printf '%s %s\n' "$(timestamp)" "$*" | tee -a "$LOG_ROOT/reviewer.log"
}

acquire_lock() {
  local lock_dir="$1"
  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    return 0
  fi
  local existing_pid=""
  if [ -f "$lock_dir/pid" ]; then
    existing_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  fi
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    return 1
  fi
  rm -rf "$lock_dir"
  mkdir "$lock_dir"
  printf '%s\n' "$$" > "$lock_dir/pid"
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
  printf '%s' "$1" | shasum -a 256 | awk '{print substr($1, 1, 16)}'
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
  /usr/bin/osascript -e "display notification \"$2\" with title \"AI review: $1\"" >/dev/null 2>&1 || true
}
