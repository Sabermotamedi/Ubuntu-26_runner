#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

cleanup_system() {
  local failed=0

  apt_cmd autoremove -y || failed=1
  apt_cmd autoclean -y || failed=1

  return "$failed"
}

verify_cleanup() {
  printf '  - [ok] cleanup has no persistent requirement\n'
}

register_group "cleanup" "Cleanup" cleanup_system verify_cleanup

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "cleanup" "$@"
fi
