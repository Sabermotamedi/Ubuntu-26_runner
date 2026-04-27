#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

CORE_PACKAGES=(
  sudo
  curl
  wget
  git
  unzip
  zip
  tar
  xz-utils
  build-essential
  software-properties-common
  ca-certificates
  gnupg
  lsb-release
  apt-transport-https
  apt-utils
  locales
  tzdata
  bash-completion
  rsync
  file
  less
  jq
  bc
  openssl
)

install_base() {
  local failed=0

  ensure_apt_updated_once || failed=1

  log_info "Upgrading installed apt packages"
  if ! apt_cmd upgrade -y; then
    log_warn "apt-get upgrade failed"
    failed=1
  fi

  apt_install_packages "${CORE_PACKAGES[@]}" || failed=1

  if command -v locale-gen >/dev/null 2>&1; then
    log_info "Ensuring en_US.UTF-8 locale exists"
    as_root locale-gen en_US.UTF-8 || failed=1
    as_root update-locale LANG=en_US.UTF-8 || log_warn "Could not update default locale"
  fi

  return "$failed"
}

verify_base() {
  check_required_cmd "sudo" sudo
  check_required_cmd "curl" curl
  check_required_cmd "wget" wget
  check_required_cmd "git" git
  check_required_cmd "unzip" unzip
  check_required_cmd "zip" zip
  check_required_cmd "tar" tar
  check_required_cmd "jq" jq
  check_required_cmd "bc" bc
  check_required_cmd "openssl" openssl
  check_required_pkg "build-essential" build-essential
  check_required_pkg "software-properties-common" software-properties-common
  check_required_pkg "ca-certificates" ca-certificates
  check_required_pkg "locales" locales
}

register_group "base" "System basics and apt upgrade" install_base verify_base

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "base" "$@"
fi
