#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

PYTHON_PACKAGES=(
  python3
  python3-pip
  python3-venv
  python-is-python3
  pipx
)

install_python() {
  apt_install_packages "${PYTHON_PACKAGES[@]}"
}

verify_python() {
  check_required_cmd "python3" python3
  check_required_cmd "python" python
  check_required_cmd "pip3" pip3
  check_required_cmd "pipx" pipx
  check_required_pkg "python3-venv" python3-venv
}

register_group "python" "Python" install_python verify_python

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "python" "$@"
fi
