#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

latest_dotnet_sdk_package() {
  apt-cache search '^dotnet-sdk-[0-9][0-9]*\.0$' 2>/dev/null | awk '{print $1}' | sort -V | tail -n 1
}

configure_microsoft_dotnet_repository() {
  local version_id
  local package_url
  local tmp_file

  if [[ -f /etc/apt/sources.list.d/microsoft-prod.list || -f /etc/apt/sources.list.d/microsoft-prod.sources ]]; then
    log_info "Microsoft package repository already configured"
    return 0
  fi

  # shellcheck disable=SC1091
  version_id="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  package_url="https://packages.microsoft.com/config/ubuntu/${version_id}/packages-microsoft-prod.deb"

  log_info "Checking Microsoft package repository for Ubuntu $version_id"
  if ! curl -fsI "$package_url" >/dev/null 2>&1; then
    log_warn "Microsoft repository package is not available for Ubuntu $version_id yet"
    return 1
  fi

  tmp_file="$(mktemp)" || return 1
  if ! curl -fsSL "$package_url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  if as_root dpkg -i "$tmp_file"; then
    rm -f "$tmp_file"
    force_apt_update
    return $?
  fi

  rm -f "$tmp_file"
  return 1
}

install_dotnet_sdk() {
  local sdk_pkg
  local failed=0

  ensure_apt_updated_once || failed=1

  sdk_pkg="$(latest_dotnet_sdk_package)"
  if [[ -z "$sdk_pkg" ]]; then
    configure_microsoft_dotnet_repository || true
    sdk_pkg="$(latest_dotnet_sdk_package)"
  fi

  if [[ -n "$sdk_pkg" ]]; then
    log_info "Installing/upgrading latest available .NET SDK package: $sdk_pkg"
    apt_install_packages "$sdk_pkg" || failed=1
  elif command -v dotnet >/dev/null 2>&1; then
    log_info ".NET is already installed: $(dotnet --version)"
  else
    log_warn "Could not find an installable .NET SDK package"
    failed=1
  fi

  return "$failed"
}

verify_dotnet() {
  check_required_cmd "dotnet" dotnet
}

register_group "dotnet" ".NET SDK" install_dotnet_sdk verify_dotnet

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "dotnet" "$@"
fi
