#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

configure_vscode_repository() {
  local arch
  local source_content
  local tmp_asc
  local tmp_gpg

  arch="$(dpkg --print-architecture)"
  as_root install -m 0755 -d /usr/share/keyrings || return 1

  if [[ -f /etc/apt/sources.list.d/vscode.list ]] && grep -q "packages.microsoft.com/repos/code" /etc/apt/sources.list.d/vscode.list; then
    log_info "Removing old VS Code source that can conflict with vscode.sources"
    as_root rm -f /etc/apt/sources.list.d/vscode.list
  fi

  if [[ ! -f /usr/share/keyrings/microsoft.gpg ]]; then
    log_info "Installing Microsoft repository signing key"
    tmp_asc="$(mktemp)" || return 1
    tmp_gpg="$(mktemp)" || {
      rm -f "$tmp_asc"
      return 1
    }

    if ! curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    if ! gpg --batch --dearmor --yes -o "$tmp_gpg" "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    as_root install -m 0644 "$tmp_gpg" /usr/share/keyrings/microsoft.gpg || {
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    }

    rm -f "$tmp_asc" "$tmp_gpg"
  else
    log_info "Microsoft repository signing key already exists"
  fi

  if [[ -f /etc/apt/sources.list.d/vscode.sources ]] && grep -q "packages.microsoft.com/repos/code" /etc/apt/sources.list.d/vscode.sources; then
    log_info "VS Code apt source already configured"
    force_apt_update
    return $?
  fi

  source_content="Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: ${arch}
Signed-By: /usr/share/keyrings/microsoft.gpg"
  write_root_file /etc/apt/sources.list.d/vscode.sources "$source_content" 0644 || return 1
  force_apt_update
}

install_vscode() {
  local failed=0

  if configure_vscode_repository; then
    apt_install_packages code || failed=1
  elif command -v code >/dev/null 2>&1; then
    log_warn "VS Code repository setup failed, but code command already exists"
  else
    failed=1
  fi

  if command -v code >/dev/null 2>&1; then
    return 0
  fi

  return "$failed"
}

install_cursor() {
  local arch
  local platform
  local api_response
  local deb_url
  local version
  local tmp_file
  local failed=0

  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64)
      platform="linux-x64"
      ;;
    arm64)
      platform="linux-arm64"
      ;;
    *)
      log_warn "Cursor does not publish a known deb package for architecture: $arch"
      return 1
      ;;
  esac

  if command -v cursor >/dev/null 2>&1; then
    log_info "Cursor already installed; checking latest stable deb"
  else
    log_info "Installing Cursor latest stable deb"
  fi

  if ! api_response="$(curl -fsSL "https://cursor.com/api/download?platform=${platform}&releaseTrack=stable")"; then
    if command -v cursor >/dev/null 2>&1; then
      log_warn "Could not check Cursor latest version, keeping existing install"
      return 0
    fi

    log_warn "Could not fetch Cursor download metadata"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    deb_url="$(printf '%s' "$api_response" | jq -r '.debUrl // empty')"
    version="$(printf '%s' "$api_response" | jq -r '.version // empty')"
  else
    deb_url="$(printf '%s' "$api_response" | sed -n 's/.*"debUrl":"\([^"]*\)".*/\1/p')"
    version="$(printf '%s' "$api_response" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  fi

  if [[ -z "$deb_url" ]]; then
    if command -v cursor >/dev/null 2>&1; then
      log_warn "Cursor metadata did not include a deb URL, keeping existing install"
      return 0
    fi

    log_warn "Cursor metadata did not include a deb URL"
    return 1
  fi

  tmp_file="$(mktemp --suffix=.deb)" || return 1
  if ! curl -fsSL "$deb_url" -o "$tmp_file"; then
    rm -f "$tmp_file"
    if command -v cursor >/dev/null 2>&1; then
      log_warn "Could not download Cursor deb, keeping existing install"
      return 0
    fi

    log_warn "Could not download Cursor deb"
    return 1
  fi

  if [[ -n "$version" ]]; then
    log_info "Installing/upgrading Cursor $version"
  else
    log_info "Installing/upgrading Cursor"
  fi

  apt_cmd install -y "$tmp_file" || failed=1
  rm -f "$tmp_file"

  if command -v cursor >/dev/null 2>&1; then
    return 0
  fi

  return "$failed"
}

install_editors() {
  local failed=0

  install_vscode || failed=1
  install_cursor || failed=1

  return "$failed"
}

verify_editors() {
  check_required_cmd "VS Code" code
  check_required_cmd "Cursor" cursor
}

register_group "editors" "VS Code and Cursor" install_editors verify_editors

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "editors" "$@"
fi
