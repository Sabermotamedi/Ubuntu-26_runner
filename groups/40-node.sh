#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091,SC2016

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

NVM_VERSION="v0.40.3"

install_nvm_and_node() {
  local target_user
  local target_home
  local nvm_dir
  local profile_file
  local failed=0

  target_user="$(get_target_user)"
  target_home="$(get_target_home)"
  nvm_dir="$target_home/.nvm"
  profile_file="$target_home/.bashrc"

  if [[ -s "$nvm_dir/nvm.sh" ]]; then
    log_info "NVM already installed for user: $target_user; checking for update"
    if ! run_as_target_user "set -o pipefail; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | PROFILE=/dev/null bash"; then
      log_warn "NVM update failed, keeping existing NVM installation"
    fi
  else
    log_info "Installing NVM $NVM_VERSION for user: $target_user"
    if ! run_as_target_user "set -o pipefail; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | PROFILE=/dev/null bash"; then
      log_warn "NVM install failed for user: $target_user"
      return 1
    fi
  fi

  ensure_line_in_user_file 'export NVM_DIR="$HOME/.nvm"' "$profile_file" || failed=1
  ensure_line_in_user_file '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' "$profile_file" || failed=1

  log_info "Installing/upgrading latest Node.js LTS via NVM"
  if ! run_as_target_user 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] || exit 1; . "$NVM_DIR/nvm.sh"; nvm install --lts; nvm alias default "lts/*"; nvm use default; corepack enable || true'; then
    log_warn "Node.js LTS install failed through NVM"
    failed=1
  fi

  return "$failed"
}

verify_node() {
  local target_home

  target_home="$(get_target_home)"
  if [[ -s "$target_home/.nvm/nvm.sh" ]] && run_as_target_user 'export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1'; then
    printf '  - [ok] Node.js LTS and npm via NVM\n'
  else
    printf '  - [missing] Node.js LTS and npm via NVM\n'
    MISSING_REQUIRED+=("Node.js LTS and npm via NVM")
  fi
}

register_group "node" "Node.js LTS via NVM" install_nvm_and_node verify_node

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "node" "$@"
fi
