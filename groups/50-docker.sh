#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

configure_docker_repository() {
  local arch
  local codename
  local repo_line

  arch="$(dpkg --print-architecture)"
  # shellcheck disable=SC1091
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"

  if [[ -z "$codename" ]]; then
    log_warn "Could not detect Ubuntu codename for Docker repository"
    return 1
  fi

  as_root install -m 0755 -d /etc/apt/keyrings || return 1

  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    log_info "Installing Docker repository signing key"
    download_root_file https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.asc 0644 || return 1
  else
    log_info "Docker repository signing key already exists"
  fi

  repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable"
  write_root_file /etc/apt/sources.list.d/docker.list "$repo_line" 0644 || return 1

  if force_apt_update; then
    return 0
  fi

  log_warn "Docker official repository is not usable on this machine; falling back to Ubuntu packages if Docker is missing"
  as_root rm -f /etc/apt/sources.list.d/docker.list
  force_apt_update || true
  return 1
}

install_docker() {
  local failed=0
  local target_user

  if command -v docker >/dev/null 2>&1; then
    log_info "Docker command already exists; apt will upgrade it if package-managed"
  fi

  if configure_docker_repository; then
    apt_install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || failed=1
  elif command -v docker >/dev/null 2>&1; then
    log_warn "Keeping existing Docker installation"
  else
    apt_install_packages docker.io || failed=1
    apt_install_first_available "Docker Compose" docker-compose-v2 docker-compose || failed=1
  fi

  if command -v docker >/dev/null 2>&1; then
    failed=0
  fi

  if command -v docker >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
    apt_install_first_available "Docker Compose" docker-compose-plugin docker-compose-v2 docker-compose || failed=1
  fi

  ensure_service_enabled_started docker || failed=1

  target_user="$(get_target_user)"
  if [[ "$target_user" != "root" ]]; then
    if ! getent group docker >/dev/null 2>&1; then
      as_root groupadd docker || failed=1
    fi

    if id -nG "$target_user" | grep -qw docker; then
      log_info "User '$target_user' already belongs to docker group"
    else
      log_info "Adding '$target_user' to docker group"
      as_root usermod -aG docker "$target_user" || failed=1
      log_info "Docker group change requires log out and log back in"
    fi
  fi

  return "$failed"
}

verify_docker() {
  check_required_cmd "docker" docker
  check_service_status "docker" docker

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf '  - [ok] docker compose plugin\n'
  else
    printf '  - [missing] docker compose plugin\n'
    MISSING_REQUIRED+=("docker compose plugin")
  fi
}

register_group "docker" "Docker" install_docker verify_docker

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "docker" "$@"
fi
