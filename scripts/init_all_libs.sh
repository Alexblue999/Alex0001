#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: scripts/init_all_libs.sh [--dry-run]

Detects common project manifests within the repository and installs their
dependencies using the appropriate package manager when available.

Options:
  --dry-run   Print the commands that would be executed without running them.
  -h, --help  Show this help message.
USAGE
}

log() {
  printf '[init-all-libs] %s\n' "$*"
}

warn() {
  printf '[init-all-libs] WARNING: %s\n' "$*" >&2
}

relpath() {
  local target="$1"
  if [[ "$target" == "$ROOT_DIR" ]]; then
    echo "."
  else
    local rel="${target#$ROOT_DIR/}"
    echo "${rel:-.}"
  fi
}

try_run() {
  local dir="$1"
  shift
  local -a cmd=("$@")
  local display_dir
  display_dir="$(relpath "$dir")"
  if ! command -v "${cmd[0]}" >/dev/null 2>&1; then
    warn "Skipping ${cmd[*]} in ${display_dir} because ${cmd[0]} is not installed."
    return 1
  fi
  if (( DRY_RUN )); then
    log "(dry-run) ${display_dir}: ${cmd[*]}"
    return 0
  fi
  log "Running in ${display_dir}: ${cmd[*]}"
  (cd "$dir" && "${cmd[@]}")
}

setup_python_env() {
  local dir="$1"
  local venv_dir="$dir/.venv"
  local rel
  rel="$(relpath "$venv_dir")"
  if ! command -v python3 >/dev/null 2>&1; then
    warn "Skipping Python environment setup in $(relpath "$dir") because python3 is unavailable."
    return 1
  fi
  if [[ ! -d "$venv_dir" ]]; then
    if (( DRY_RUN )); then
      log "(dry-run) Would create Python virtualenv at ${rel}."
    else
      log "Creating Python virtualenv at ${rel}."
      if ! python3 -m venv "$venv_dir"; then
        warn "Failed to create virtualenv at ${rel}."
        return 1
      fi
    fi
  fi
  if (( DRY_RUN )); then
    echo "$venv_dir/bin/pip"
    return 0
  fi
  if [[ ! -x "$venv_dir/bin/pip" ]]; then
    warn "pip executable missing in ${rel}; attempting to bootstrap."
    "$venv_dir/bin/python" -m ensurepip --upgrade || true
  fi
  echo "$venv_dir/bin/pip"
}

init_node_projects() {
  declare -A seen_dirs=()
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    if [[ -n "${seen_dirs[$dir]:-}" ]]; then
      continue
    fi
    seen_dirs[$dir]=1
    local manager=""
    local -a args=()
    if [[ -f "$dir/pnpm-lock.yaml" ]]; then
      manager="pnpm"
      args=(install)
    elif [[ -f "$dir/yarn.lock" ]]; then
      manager="yarn"
      args=(install)
    elif [[ -f "$dir/package-lock.json" || -f "$dir/npm-shrinkwrap.json" ]]; then
      manager="npm"
      args=(install)
    elif command -v pnpm >/dev/null 2>&1; then
      manager="pnpm"
      args=(install)
    elif command -v yarn >/dev/null 2>&1; then
      manager="yarn"
      args=(install)
    else
      manager="npm"
      args=(install)
    fi
    try_run "$dir" "$manager" "${args[@]}"
  done < <(find "$ROOT_DIR" -type f -name package.json \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*')
}

init_python_projects() {
  declare -A pip_envs=()
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    local pip_bin=""
    pip_bin="${pip_envs[$dir]:-}"
    if [[ -z "$pip_bin" ]]; then
      if pip_bin="$(setup_python_env "$dir")"; then
        pip_envs[$dir]="$pip_bin"
      else
        continue
      fi
    fi
    try_run "$dir" "$pip_bin" install -r "$file"
  done < <(find "$ROOT_DIR" -type f -name 'requirements*.txt' \
    -not -path '*/.venv/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*')

  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    if grep -q "^\[tool.poetry\]" "$file" 2>/dev/null || [[ -f "$dir/poetry.lock" ]]; then
      try_run "$dir" poetry install
    elif grep -q "^\[tool.pdm\]" "$file" 2>/dev/null || [[ -f "$dir/pdm.lock" ]]; then
      try_run "$dir" pdm install
    else
      local pip_bin=""
      pip_bin="${pip_envs[$dir]:-}"
      if [[ -z "$pip_bin" ]]; then
        if pip_bin="$(setup_python_env "$dir")"; then
          pip_envs[$dir]="$pip_bin"
        else
          continue
        fi
      fi
      try_run "$dir" "$pip_bin" install --upgrade pip
      try_run "$dir" "$pip_bin" install -e "$dir"
    fi
  done < <(find "$ROOT_DIR" -type f -name pyproject.toml \
    -not -path '*/.venv/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*')

  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" pipenv install
  done < <(find "$ROOT_DIR" -type f -name Pipfile \
    -not -path '*/.venv/*' \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*')
}

init_rust_projects() {
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" cargo fetch
  done < <(find "$ROOT_DIR" -type f -name Cargo.toml \
    -not -path '*/target/*' \
    -not -path '*/.git/*')
}

init_go_projects() {
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" go mod download
  done < <(find "$ROOT_DIR" -type f -name go.mod \
    -not -path '*/vendor/*' \
    -not -path '*/.git/*')
}

init_ruby_projects() {
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" bundle install
  done < <(find "$ROOT_DIR" -type f -name Gemfile \
    -not -path '*/.git/*')
}

init_php_projects() {
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" composer install
  done < <(find "$ROOT_DIR" -type f -name composer.json \
    -not -path '*/vendor/*' \
    -not -path '*/.git/*')
}

init_dotnet_projects() {
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" dotnet restore
  done < <(find "$ROOT_DIR" -type f \( -name '*.csproj' -o -name '*.sln' \) \
    -not -path '*/obj/*' \
    -not -path '*/bin/*' \
    -not -path '*/.git/*')
}

init_java_projects() {
  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    if [[ "$file" == *.gradle || "$file" == *.gradle.kts ]]; then
      try_run "$dir" ./gradlew dependencies
    fi
  done < <(find "$ROOT_DIR" -type f \( -name 'build.gradle' -o -name 'build.gradle.kts' \) \
    -not -path '*/.git/*')

  while IFS= read -r file; do
    local dir="$(dirname "$file")"
    try_run "$dir" mvn dependency:go-offline
  done < <(find "$ROOT_DIR" -type f -name pom.xml \
    -not -path '*/.git/*')
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        warn "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  log "Initializing dependencies in $(relpath "$ROOT_DIR")"
  init_node_projects
  init_python_projects
  init_rust_projects
  init_go_projects
  init_ruby_projects
  init_php_projects
  init_dotnet_projects
  init_java_projects
  log "All dependency initialization steps completed."
}

main "$@"
