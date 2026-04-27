#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

DEV_PACKAGES=(
  pkg-config
  cmake
  ninja-build
  autoconf
  automake
  libtool
  libssl-dev
  zlib1g-dev
  libffi-dev
  libreadline-dev
  libsqlite3-dev
  libbz2-dev
  liblzma-dev
)

install_dev_libraries() {
  apt_install_packages "${DEV_PACKAGES[@]}"
}

verify_dev_libraries() {
  check_required_cmd "pkg-config" pkg-config
  check_required_cmd "cmake" cmake
  check_required_cmd "ninja" ninja
  check_required_cmd "autoconf" autoconf
  check_required_cmd "automake" automake
  check_required_pkg "OpenSSL development files" libssl-dev
  check_required_pkg "zlib development files" zlib1g-dev
  check_required_pkg "libffi development files" libffi-dev
}

register_group "dev-libraries" "Development libraries" install_dev_libraries verify_dev_libraries

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "dev-libraries" "$@"
fi
