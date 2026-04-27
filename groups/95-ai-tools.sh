#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091,SC2016

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

install_opencode() {
  local target_user
  local target_home
  local opencode_bin
  local profile_file
  local failed=0

  target_user="$(get_target_user)"
  target_home="$(get_target_home)"
  opencode_bin="$target_home/.opencode/bin/opencode"
  profile_file="$target_home/.bashrc"

  if [[ -x "$opencode_bin" ]]; then
    log_info "OpenCode already installed for user: $target_user; checking for update"
  else
    log_info "Installing OpenCode for user: $target_user"
  fi

  if ! run_as_target_user 'set -o pipefail; curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path'; then
    if [[ -x "$opencode_bin" ]]; then
      log_warn "OpenCode update failed, keeping existing install"
    else
      log_warn "OpenCode install failed"
      failed=1
    fi
  fi

  ensure_line_in_user_file 'export PATH="$HOME/.opencode/bin:$PATH"' "$profile_file" || failed=1
  ensure_line_in_user_file 'export PATH="$HOME/.opencode/bin:$PATH"' "$target_home/.profile" || failed=1

  if [[ -x "$opencode_bin" ]] || run_as_target_user 'export PATH="$HOME/.opencode/bin:$PATH"; command -v opencode >/dev/null 2>&1'; then
    return "$failed"
  fi

  return 1
}

verify_ai_tools() {
  local target_home

  target_home="$(get_target_home)"
  if [[ -x "$target_home/.opencode/bin/opencode" ]] && run_as_target_user 'export PATH="$HOME/.opencode/bin:$PATH"; opencode --version >/dev/null 2>&1'; then
    printf '  - [ok] OpenCode\n'
  else
    printf '  - [missing] OpenCode\n'
    MISSING_REQUIRED+=("OpenCode")
  fi
}

register_group "ai-tools" "OpenCode" install_opencode verify_ai_tools

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "ai-tools" "$@"
fi
