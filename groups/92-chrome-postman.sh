#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

configure_google_chrome_repository() {
  local arch
  local repo_line
  local tmp_asc
  local tmp_gpg

  arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then
    log_warn "Google Chrome stable is only available from Google for amd64; detected: $arch"
    return 1
  fi

  as_root install -m 0755 -d /etc/apt/keyrings || return 1

  if [[ -f /etc/apt/sources.list.d/google-chrome.sources ]] && grep -q "dl.google.com/linux/chrome-stable/deb" /etc/apt/sources.list.d/google-chrome.sources; then
    log_info "Removing old Google Chrome apt source: /etc/apt/sources.list.d/google-chrome.sources"
    as_root rm -f /etc/apt/sources.list.d/google-chrome.sources || return 1
  fi

  if [[ ! -f /etc/apt/keyrings/google-chrome.gpg ]]; then
    log_info "Installing Google Chrome repository signing key"
    tmp_asc="$(mktemp)" || return 1
    tmp_gpg="$(mktemp)" || {
      rm -f "$tmp_asc"
      return 1
    }

    if ! curl -fsSL https://dl.google.com/linux/linux_signing_key.pub -o "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    if ! gpg --batch --dearmor --yes -o "$tmp_gpg" "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    as_root install -m 0644 "$tmp_gpg" /etc/apt/keyrings/google-chrome.gpg || {
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    }

    rm -f "$tmp_asc" "$tmp_gpg"
  else
    log_info "Google Chrome repository signing key already exists"
  fi

  repo_line="deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main"
  write_root_file /etc/apt/sources.list.d/google-chrome.list "$repo_line" 0644 || return 1
  force_apt_update
}

install_google_chrome() {
  local failed=0

  if configure_google_chrome_repository; then
    apt_install_packages google-chrome-stable || failed=1
  elif command -v google-chrome >/dev/null 2>&1 || command -v google-chrome-stable >/dev/null 2>&1; then
    log_warn "Google Chrome repository setup failed, but Chrome already exists"
  else
    failed=1
  fi

  if command -v google-chrome >/dev/null 2>&1 || command -v google-chrome-stable >/dev/null 2>&1; then
    return 0
  fi

  return "$failed"
}

install_postman() {
  local failed=0

  apt_install_packages snapd || failed=1

  if has_systemd; then
    as_root systemctl enable --now snapd.socket || log_warn "Could not enable/start snapd.socket"
  fi

  if ! command -v snap >/dev/null 2>&1; then
    log_warn "snap command is not available after installing snapd"
    return 1
  fi

  as_root snap wait system seed.loaded >/dev/null 2>&1 || true

  if snap list postman >/dev/null 2>&1; then
    log_info "Refreshing Postman snap"
    as_root snap refresh postman || failed=1
  else
    log_info "Installing Postman snap"
    as_root snap install postman || failed=1
  fi

  if snap list postman >/dev/null 2>&1 || command -v postman >/dev/null 2>&1 || [[ -x /snap/bin/postman ]]; then
    return "$failed"
  fi

  return 1
}

install_chrome_postman() {
  local failed=0

  install_google_chrome || failed=1
  install_postman || failed=1

  return "$failed"
}

check_google_chrome() {
  if command -v google-chrome >/dev/null 2>&1 || command -v google-chrome-stable >/dev/null 2>&1; then
    printf '  - [ok] Google Chrome\n'
  else
    printf '  - [missing] Google Chrome\n'
    MISSING_REQUIRED+=("Google Chrome")
  fi
}

check_postman() {
  if command -v postman >/dev/null 2>&1 || [[ -x /snap/bin/postman ]] || (command -v snap >/dev/null 2>&1 && snap list postman >/dev/null 2>&1); then
    printf '  - [ok] Postman\n'
  else
    printf '  - [missing] Postman\n'
    MISSING_REQUIRED+=("Postman")
  fi
}

verify_chrome_postman() {
  check_google_chrome
  check_postman
}

register_group "chrome-postman" "Google Chrome and Postman" install_chrome_postman verify_chrome_postman

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "chrome-postman" "$@"
fi
