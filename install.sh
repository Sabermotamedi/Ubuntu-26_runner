#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${UBUNTU_26_RUNNER_OWNER:-Sabermotamedi}"
REPO_NAME="${UBUNTU_26_RUNNER_REPO:-Ubuntu-26_runner}"
REPO_REF="${UBUNTU_26_RUNNER_REF:-main}"
ARCHIVE_URL="${UBUNTU_26_RUNNER_ARCHIVE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz}"
WORK_DIR=""

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

find_local_setup_script() {
  local script_source="${BASH_SOURCE[0]:-}"

  if [[ -z "$script_source" || "$script_source" == "bash" || ! -f "$script_source" ]]; then
    return 1
  fi

  local script_dir
  script_dir="$(cd -- "$(dirname -- "$script_source")" && pwd)"

  local setup_script="$script_dir/setup.sh"
  if [[ ! -f "$setup_script" ]]; then
    return 1
  fi

  printf '%s\n' "$setup_script"
}

setup_needs_sudo() {
  local arg

  if [[ "$(id -u)" -eq 0 ]]; then
    return 1
  fi

  for arg in "$@"; do
    case "$arg" in
      --list|--verify|-h|--help)
        return 1
        ;;
    esac
  done

  return 0
}

run_setup() {
  local setup_script="$1"
  shift

  if [[ ! -x "$setup_script" ]]; then
    chmod +x "$setup_script"
  fi

  if setup_needs_sudo "$@"; then
    command -v sudo >/dev/null 2>&1 || die "sudo is required to run setup installs"

    if [[ -n "${BOOTSTRAP_LOG_DIR:-}" && -z "${SETUP_LOG_DIR:-}" && -z "${SETUP_LOG_FILE:-}" ]]; then
      sudo SETUP_LOG_DIR="$BOOTSTRAP_LOG_DIR" "$setup_script" "$@"
    else
      sudo "$setup_script" "$@"
    fi
    return
  fi

  if [[ -n "${BOOTSTRAP_LOG_DIR:-}" && -z "${SETUP_LOG_DIR:-}" && -z "${SETUP_LOG_FILE:-}" ]]; then
    SETUP_LOG_DIR="$BOOTSTRAP_LOG_DIR" "$setup_script" "$@"
  else
    "$setup_script" "$@"
  fi
}

download_archive() {
  local url="$1"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
    return
  fi

  die "curl or wget is required to download ${url}"
}

main() {
  local setup_script
  if setup_script="$(find_local_setup_script)"; then
    run_setup "$setup_script" "$@"
    return
  fi

  command -v tar >/dev/null 2>&1 || die "tar is required to unpack the setup archive"
  command -v mktemp >/dev/null 2>&1 || die "mktemp is required to create a temporary directory"

  WORK_DIR="$(mktemp -d)"
  trap cleanup EXIT

  if [[ -z "${SETUP_LOG_DIR:-}" && -z "${SETUP_LOG_FILE:-}" ]]; then
    local default_log_dir="${HOME:-/tmp}/.local/state/ubuntu-26-runner/logs"
    mkdir -p "$default_log_dir"
    BOOTSTRAP_LOG_DIR="$default_log_dir"
    export BOOTSTRAP_LOG_DIR
  fi

  printf 'Downloading %s (%s)...\n' "${REPO_OWNER}/${REPO_NAME}" "$REPO_REF"
  download_archive "$ARCHIVE_URL" | tar -xz -C "$WORK_DIR"

  local entries=("$WORK_DIR"/*)
  if [[ "${#entries[@]}" -ne 1 || ! -d "${entries[0]}" ]]; then
    die "downloaded archive did not unpack to one directory"
  fi

  setup_script="${entries[0]}/setup.sh"
  [[ -f "$setup_script" ]] || die "downloaded archive does not contain setup.sh"

  run_setup "$setup_script" "$@"
}

main "$@"
