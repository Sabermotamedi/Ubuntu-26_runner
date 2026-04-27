#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

TOOL_PACKAGES=(
  htop
  neovim
  tmux
  fzf
  tree
  net-tools
  dnsutils
  iputils-ping
  traceroute
  lsof
  ripgrep
  shellcheck
  cron
  logrotate
  unattended-upgrades
  ufw
  fail2ban
)

install_useful_tools() {
  local failed=0

  apt_install_packages "${TOOL_PACKAGES[@]}" || failed=1

  ensure_service_enabled_started cron || failed=1
  ensure_service_enabled_started fail2ban || failed=1
  ensure_service_enabled_started unattended-upgrades || failed=1

  return "$failed"
}

verify_useful_tools() {
  check_required_cmd "htop" htop
  check_required_cmd "nvim" nvim
  check_required_cmd "tmux" tmux
  check_required_cmd "fzf" fzf
  check_required_cmd "tree" tree
  check_required_cmd "ripgrep" rg
  check_required_cmd "shellcheck" shellcheck
  check_required_cmd "netstat" netstat
  check_required_cmd "ping" ping
  check_required_cmd "dig" dig
  check_required_cmd "lsof" lsof
  check_required_pkg "cron" cron
  check_required_pkg "logrotate" logrotate
  check_required_pkg "unattended-upgrades" unattended-upgrades
  check_required_pkg "ufw" ufw
  check_required_pkg "fail2ban" fail2ban
  check_service_status "cron" cron
  check_service_status "fail2ban" fail2ban
}

register_group "tools" "Useful tools and services" install_useful_tools verify_useful_tools

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "tools" "$@"
fi
