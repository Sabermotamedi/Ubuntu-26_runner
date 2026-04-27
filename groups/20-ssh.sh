#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

install_ssh() {
  local failed=0

  apt_install_packages openssh-client openssh-server || failed=1
  ensure_service_enabled_started ssh || failed=1

  return "$failed"
}

verify_ssh() {
  check_required_cmd "ssh client" ssh
  check_required_pkg "OpenSSH server" openssh-server
  check_service_status "ssh" ssh
}

register_group "ssh" "OpenSSH Server" install_ssh verify_ssh

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "ssh" "$@"
fi
