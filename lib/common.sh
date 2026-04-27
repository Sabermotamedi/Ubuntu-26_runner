#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2016,SC2317,SC2329

if [[ -n "${SETUP_COMMON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_COMMON_LOADED=1

set -uo pipefail

export DEBIAN_FRONTEND=noninteractive

SUPPORTED_UBUNTU_MAJOR="${SUPPORTED_UBUNTU_MAJOR:-26}"
APT_UPDATED=0
SETUP_LOG_CAPTURE_STARTED=0

FAILED_STEPS=()
FAILED_PACKAGES=()
WARNINGS=()
MISSING_REQUIRED=()

GROUP_NAMES=()
GROUP_DESCS=()
GROUP_INSTALL_FNS=()
GROUP_VERIFY_FNS=()

log_section() {
  printf '\n==================================================\n'
  printf '== %s\n' "$1"
  printf '==================================================\n'
}

log_info() {
  printf '  - %s\n' "$1"
}

log_warn() {
  printf '  - WARNING: %s\n' "$1"
  WARNINGS+=("$1")
}

log_error() {
  printf '  - ERROR: %s\n' "$1"
}

run_step() {
  local name="$1"
  shift

  log_section "$name"
  "$@"
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    log_warn "Step needs attention: $name"
    FAILED_STEPS+=("$name")
  else
    log_info "Step completed: $name"
  fi

  return 0
}

require_sudo() {
  if [[ "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    log_error "sudo is required when running this script as a non-root user."
    exit 1
  fi
}

validate_sudo_session() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  log_info "Sudo validation required. You may be prompted for your password once."
  if ! sudo -v; then
    log_error "Could not validate sudo access."
    exit 1
  fi
}

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

start_setup_log_capture() {
  if [[ "$SETUP_LOG_CAPTURE_STARTED" -eq 1 ]]; then
    return 0
  fi

  local common_dir
  local project_dir
  local log_dir
  local log_file
  local timestamp

  common_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || {
    log_warn "Could not determine setup log directory"
    return 1
  }
  project_dir="$(cd -- "$common_dir/.." && pwd)" || {
    log_warn "Could not determine setup log directory"
    return 1
  }

  if [[ -n "${SETUP_LOG_FILE:-}" ]]; then
    log_file="$SETUP_LOG_FILE"
    log_dir="$(dirname -- "$log_file")"
  else
    log_dir="${SETUP_LOG_DIR:-$project_dir/logs}"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    log_file="$log_dir/setup-$timestamp.log"
  fi

  if ! mkdir -p "$log_dir" || ! : >>"$log_file"; then
    log_warn "Could not create setup log file: $log_file"
    return 1
  fi

  SETUP_LOG_CAPTURE_STARTED=1
  export SETUP_LOG_FILE="$log_file"
  exec > >(tee -a "$log_file") 2>&1
  log_info "Saving setup log to: $log_file"
}

apt_cmd() {
  as_root apt-get -o DPkg::Lock::Timeout=180 "$@"
}

check_ubuntu_version() {
  if [[ ! -r /etc/os-release ]]; then
    log_error "/etc/os-release was not found. Cannot verify Ubuntu version."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    log_error "This setup is intended for Ubuntu ${SUPPORTED_UBUNTU_MAJOR}.x only. Detected: ${PRETTY_NAME:-unknown}."
    exit 1
  fi

  case "${VERSION_ID:-}" in
    "${SUPPORTED_UBUNTU_MAJOR}"|"${SUPPORTED_UBUNTU_MAJOR}."*)
      log_info "Ubuntu version supported: ${PRETTY_NAME:-Ubuntu ${VERSION_ID}}"
      ;;
    *)
      log_error "This setup is intended for Ubuntu ${SUPPORTED_UBUNTU_MAJOR}.x only. Detected: ${PRETTY_NAME:-Ubuntu ${VERSION_ID:-unknown}}."
      exit 1
      ;;
  esac
}

has_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

repair_known_apt_source_conflicts() {
  if [[ -f /etc/apt/sources.list.d/vscode.list && -f /etc/apt/sources.list.d/vscode.sources ]] && grep -q "packages.microsoft.com/repos/code" /etc/apt/sources.list.d/vscode.list; then
    log_info "Removing conflicting old VS Code apt source: /etc/apt/sources.list.d/vscode.list"
    as_root rm -f /etc/apt/sources.list.d/vscode.list
  fi

  if [[ -f /etc/apt/sources.list.d/pgadmin4.list ]] && grep -q "ftp.postgresql.org/pub/pgadmin" /etc/apt/sources.list.d/pgadmin4.list; then
    log_info "Removing stale pgAdmin apt source before validation"
    as_root rm -f /etc/apt/sources.list.d/pgadmin4.list
  fi
}

is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

apt_package_available() {
  apt-cache show "$1" >/dev/null 2>&1
}

ensure_apt_updated_once() {
  if [[ "$APT_UPDATED" -eq 1 ]]; then
    return 0
  fi

  log_info "Updating package lists"
  if apt_cmd update; then
    APT_UPDATED=1
    return 0
  fi

  log_warn "apt-get update failed"
  return 1
}

force_apt_update() {
  log_info "Refreshing package lists"
  if apt_cmd update; then
    APT_UPDATED=1
    return 0
  fi

  log_warn "apt-get update failed"
  return 1
}

apt_install_packages() {
  local pkg
  local failed=0

  if ! ensure_apt_updated_once; then
    return 1
  fi

  for pkg in "$@"; do
    if is_pkg_installed "$pkg"; then
      log_info "$pkg already installed; checking for upgrade"
    else
      log_info "Installing $pkg"
    fi

    if ! apt_cmd install -y "$pkg"; then
      log_warn "Could not install or upgrade package: $pkg"
      FAILED_PACKAGES+=("$pkg")
      failed=1
    fi
  done

  return "$failed"
}

apt_install_first_available() {
  local label="$1"
  shift

  local pkg
  for pkg in "$@"; do
    if apt_package_available "$pkg"; then
      apt_install_packages "$pkg"
      return $?
    fi
  done

  log_warn "No apt package found for $label. Tried: $*"
  return 1
}

write_root_file() {
  local destination="$1"
  local content="$2"
  local mode="${3:-0644}"
  local tmp_file

  tmp_file="$(mktemp)" || return 1
  printf '%s\n' "$content" >"$tmp_file"

  if as_root install -m "$mode" "$tmp_file" "$destination"; then
    rm -f "$tmp_file"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

download_root_file() {
  local url="$1"
  local destination="$2"
  local mode="${3:-0644}"
  local tmp_file

  tmp_file="$(mktemp)" || return 1

  if ! curl -fsSL "$url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  if as_root install -m "$mode" "$tmp_file" "$destination"; then
    rm -f "$tmp_file"
    return 0
  fi

  rm -f "$tmp_file"
  return 1
}

get_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
  else
    id -un
  fi
}

get_target_home() {
  local target_user
  local target_home

  target_user="$(get_target_user)"
  target_home="$(getent passwd "$target_user" | cut -d: -f6)"

  if [[ -n "$target_home" ]]; then
    printf '%s\n' "$target_home"
  elif [[ "$target_user" == "root" ]]; then
    printf '%s\n' "/root"
  else
    printf '/home/%s\n' "$target_user"
  fi
}

run_as_target_user() {
  local cmd="$1"
  local target_user
  local current_user

  target_user="$(get_target_user)"
  current_user="$(id -un)"

  if [[ "$target_user" == "$current_user" ]]; then
    HOME="$(get_target_home)" bash -lc "$cmd"
  elif [[ "$target_user" == "root" ]]; then
    HOME="$(get_target_home)" bash -lc "$cmd"
  else
    sudo -u "$target_user" -H bash -lc "$cmd"
  fi
}

ensure_line_in_user_file() {
  local line="$1"
  local file="$2"
  local target_user

  target_user="$(get_target_user)"

  if [[ "$target_user" == "root" ]]; then
    touch "$file"
    grep -Fqx "$line" "$file" || printf '%s\n' "$line" >>"$file"
    return $?
  fi

  sudo -u "$target_user" -H bash -c '
    target_file="$1"
    wanted_line="$2"
    touch "$target_file"
    grep -Fqx "$wanted_line" "$target_file" || printf "%s\n" "$wanted_line" >>"$target_file"
  ' _ "$file" "$line"
}

ensure_service_enabled_started() {
  local service="$1"

  if ! has_systemd; then
    log_warn "systemd is not available; skipping service enable/start for $service"
    return 0
  fi

  log_info "Enabling and starting $service"
  if as_root systemctl enable --now "$service"; then
    return 0
  fi

  log_warn "Could not enable/start service: $service"
  return 1
}

check_required_cmd() {
  local label="$1"
  local cmd="$2"

  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  - [ok] %s\n' "$label"
  else
    printf '  - [missing] %s\n' "$label"
    MISSING_REQUIRED+=("$label")
  fi
}

check_required_pkg() {
  local label="$1"
  local pkg="$2"

  if is_pkg_installed "$pkg"; then
    printf '  - [ok] %s\n' "$label"
  else
    printf '  - [missing] %s\n' "$label"
    MISSING_REQUIRED+=("$label")
  fi
}

check_service_status() {
  local label="$1"
  local service="$2"

  if ! has_systemd; then
    printf '  - [skipped] %s service, systemd not available\n' "$label"
    return 0
  fi

  if systemctl is-enabled "$service" >/dev/null 2>&1 && systemctl is-active "$service" >/dev/null 2>&1; then
    printf '  - [ok] %s service active/enabled\n' "$label"
  else
    printf '  - [missing] %s service active/enabled\n' "$label"
    MISSING_REQUIRED+=("$label service")
  fi
}

register_group() {
  local name="$1"
  local description="$2"
  local install_fn="$3"
  local verify_fn="$4"

  GROUP_NAMES+=("$name")
  GROUP_DESCS+=("$description")
  GROUP_INSTALL_FNS+=("$install_fn")
  GROUP_VERIFY_FNS+=("$verify_fn")
}

load_groups_from_dir() {
  local groups_dir="$1"
  local group_file

  if [[ ! -d "$groups_dir" ]]; then
    log_error "Groups directory not found: $groups_dir"
    exit 1
  fi

  shopt -s nullglob
  for group_file in "$groups_dir"/*.sh; do
    # shellcheck disable=SC1090
    source "$group_file"
  done
  shopt -u nullglob

  if [[ "${#GROUP_NAMES[@]}" -eq 0 ]]; then
    log_error "No setup groups were found in: $groups_dir"
    exit 1
  fi
}

get_group_index() {
  local wanted="$1"
  local i

  for i in "${!GROUP_NAMES[@]}"; do
    if [[ "${GROUP_NAMES[$i]}" == "$wanted" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}

group_exists() {
  get_group_index "$1" >/dev/null 2>&1
}

list_groups() {
  local i

  printf '%-24s %s\n' "GROUP" "DESCRIPTION"
  printf '%-24s %s\n' "-----" "-----------"
  for i in "${!GROUP_NAMES[@]}"; do
    printf '%-24s %s\n' "${GROUP_NAMES[$i]}" "${GROUP_DESCS[$i]}"
  done
}

split_group_list() {
  local input="$1"
  local -n target="$2"
  local part
  local items=()

  IFS=',' read -r -a items <<<"$input"
  for part in "${items[@]}"; do
    part="${part//[[:space:]]/}"
    if [[ -n "$part" ]]; then
      target+=("$part")
    fi
  done
}

array_contains() {
  local wanted="$1"
  shift

  local item
  for item in "$@"; do
    if [[ "$item" == "$wanted" ]]; then
      return 0
    fi
  done

  return 1
}

validate_group_names() {
  local group_name
  local failed=0

  for group_name in "$@"; do
    if ! group_exists "$group_name"; then
      log_error "Unknown group: $group_name"
      failed=1
    fi
  done

  if [[ "$failed" -ne 0 ]]; then
    printf '\nAvailable groups:\n'
    list_groups
    exit 2
  fi
}

select_groups() {
  local -n result="$1"
  local -n only_groups="$2"
  local -n skip_groups="$3"
  local group_name

  result=()
  for group_name in "${GROUP_NAMES[@]}"; do
    if [[ "${#only_groups[@]}" -gt 0 ]] && ! array_contains "$group_name" "${only_groups[@]}"; then
      continue
    fi

    if [[ "${#skip_groups[@]}" -gt 0 ]] && array_contains "$group_name" "${skip_groups[@]}"; then
      continue
    fi

    result+=("$group_name")
  done
}

run_group_install() {
  local group_name="$1"
  local label="${2:-}"
  local index
  local install_fn

  index="$(get_group_index "$group_name")" || return 1
  install_fn="${GROUP_INSTALL_FNS[$index]}"

  if [[ -z "$label" ]]; then
    label="${GROUP_DESCS[$index]}"
  fi

  run_step "$label" "$install_fn"
}

run_selected_group_installs() {
  local group_name
  local index
  local step_number=1
  local label

  for group_name in "$@"; do
    index="$(get_group_index "$group_name")" || return 1
    label="${step_number}) ${GROUP_DESCS[$index]}"
    run_group_install "$group_name" "$label"
    step_number=$((step_number + 1))
  done
}

verify_group() {
  local group_name="$1"
  local index
  local verify_fn

  index="$(get_group_index "$group_name")" || return 1
  verify_fn="${GROUP_VERIFY_FNS[$index]}"
  "$verify_fn"
}

verify_selected_groups() {
  local group_name

  MISSING_REQUIRED=()
  log_section "Final verification report"

  for group_name in "$@"; do
    verify_group "$group_name"
  done

  if [[ "${#FAILED_PACKAGES[@]}" -gt 0 ]]; then
    printf '\nPackages that need attention:\n'
    printf '  - %s\n' "${FAILED_PACKAGES[@]}"
  fi

  if [[ "${#FAILED_STEPS[@]}" -gt 0 ]]; then
    printf '\nSteps that need attention:\n'
    printf '  - %s\n' "${FAILED_STEPS[@]}"
  fi

  if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
    printf '\nWarnings:\n'
    printf '  - %s\n' "${WARNINGS[@]}"
  fi

  if [[ "${#MISSING_REQUIRED[@]}" -gt 0 ]]; then
    printf '\nMissing required items:\n'
    printf '  - %s\n' "${MISSING_REQUIRED[@]}"
    return 1
  fi

  if [[ "${#FAILED_STEPS[@]}" -gt 0 || "${#FAILED_PACKAGES[@]}" -gt 0 ]]; then
    return 1
  fi

  return 0
}

bootstrap_setup() {
  require_sudo
  validate_sudo_session
  check_ubuntu_version
  repair_known_apt_source_conflicts
}

run_group_file_cli() {
  local group_name="$1"
  shift

  local verify_only=0
  local arg

  for arg in "$@"; do
    case "$arg" in
      --verify)
        verify_only=1
        ;;
      -h|--help)
        printf 'Usage: sudo %s [--verify]\n' "$0"
        printf 'Runs only the %s setup group.\n' "$group_name"
        exit 0
        ;;
      *)
        log_error "Unknown option for group script: $arg"
        exit 2
        ;;
    esac
  done

  if [[ "$verify_only" -eq 1 ]]; then
    start_setup_log_capture
    check_ubuntu_version
    if verify_selected_groups "$group_name"; then
      exit 0
    fi
    exit 1
  fi

  start_setup_log_capture
  bootstrap_setup
  run_group_install "$group_name"
  if verify_selected_groups "$group_name"; then
    log_section "Group complete"
    log_info "Group '$group_name' completed successfully."
    exit 0
  fi

  log_section "Group completed with attention needed"
  log_info "Review the report above, fix the listed problem, then run this group again."
  exit 1
}
