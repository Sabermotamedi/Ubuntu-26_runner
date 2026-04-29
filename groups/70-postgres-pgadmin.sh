#!/usr/bin/env bash
# shellcheck shell=bash disable=SC1091

GROUP_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$GROUP_SCRIPT_DIR/../lib/common.sh"

POSTGRES_PACKAGES=(
  postgresql
  postgresql-client
  libpq-dev
)

configure_pgadmin_repository() {
  local codename
  local release_url
  local repo_line
  local tmp_asc
  local tmp_gpg

  # shellcheck disable=SC1091
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"

  if [[ -z "$codename" ]]; then
    log_warn "Could not detect Ubuntu codename for pgAdmin repository"
    return 1
  fi

  release_url="https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${codename}/dists/pgadmin4/Release"
  if ! curl -fsI "$release_url" >/dev/null 2>&1; then
    log_warn "pgAdmin apt repository is not published for Ubuntu codename: $codename"
    return 1
  fi

  as_root install -m 0755 -d /etc/apt/keyrings || return 1

  if [[ ! -f /etc/apt/keyrings/pgadmin.gpg ]]; then
    log_info "Installing pgAdmin repository signing key"
    tmp_asc="$(mktemp)" || return 1
    tmp_gpg="$(mktemp)" || {
      rm -f "$tmp_asc"
      return 1
    }

    if ! curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub -o "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    if ! gpg --batch --dearmor --yes -o "$tmp_gpg" "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    as_root install -m 0644 "$tmp_gpg" /etc/apt/keyrings/pgadmin.gpg || {
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    }

    rm -f "$tmp_asc" "$tmp_gpg"
  else
    log_info "pgAdmin repository signing key already exists"
  fi

  repo_line="deb [signed-by=/etc/apt/keyrings/pgadmin.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${codename} pgadmin4 main"
  write_root_file /etc/apt/sources.list.d/pgadmin4.list "$repo_line" 0644 || return 1
  force_apt_update
}

configure_dbeaver_repository() {
  local arch
  local repo_line
  local tmp_asc
  local tmp_gpg

  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64)
      ;;
    *)
      log_warn "DBeaver CE is only available from DBeaver's apt repository for amd64 and arm64; detected: $arch"
      return 1
      ;;
  esac

  as_root install -m 0755 -d /etc/apt/keyrings || return 1

  if [[ ! -f /etc/apt/keyrings/dbeaver.gpg ]]; then
    log_info "Installing DBeaver repository signing key"
    tmp_asc="$(mktemp)" || return 1
    tmp_gpg="$(mktemp)" || {
      rm -f "$tmp_asc"
      return 1
    }

    if ! curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key -o "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    if ! gpg --batch --dearmor --yes -o "$tmp_gpg" "$tmp_asc"; then
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    fi

    as_root install -m 0644 "$tmp_gpg" /etc/apt/keyrings/dbeaver.gpg || {
      rm -f "$tmp_asc" "$tmp_gpg"
      return 1
    }

    rm -f "$tmp_asc" "$tmp_gpg"
  else
    log_info "DBeaver repository signing key already exists"
  fi

  repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver-ce /"
  write_root_file /etc/apt/sources.list.d/dbeaver.list "$repo_line" 0644 || return 1
  force_apt_update
}

install_dbeaver() {
  local failed=0

  if configure_dbeaver_repository; then
    apt_install_packages dbeaver-ce || failed=1
  elif is_pkg_installed dbeaver-ce || command -v dbeaver >/dev/null 2>&1; then
    log_warn "DBeaver repository setup failed, but DBeaver is already installed"
  else
    failed=1
  fi

  if is_pkg_installed dbeaver-ce || command -v dbeaver >/dev/null 2>&1; then
    return "$failed"
  fi

  return 1
}

install_pgadmin_snap() {
  local failed=0

  log_info "Installing/upgrading pgAdmin 4 from snap"
  apt_install_packages snapd || failed=1

  if has_systemd; then
    as_root systemctl enable --now snapd.socket || log_warn "Could not enable/start snapd.socket"
    as_root systemctl enable --now snapd.service || log_warn "Could not enable/start snapd.service"
  fi

  if ! command -v snap >/dev/null 2>&1; then
    log_warn "snap command is not available after installing snapd"
    return 1
  fi

  if snap list pgadmin4 >/dev/null 2>&1; then
    as_root snap refresh pgadmin4 || failed=1
  else
    as_root snap install pgadmin4 || failed=1
  fi

  as_root snap connect pgadmin4:home >/dev/null 2>&1 || true
  as_root snap connect pgadmin4:password-manager-service >/dev/null 2>&1 || true

  return "$failed"
}

install_postgres_pgadmin() {
  local failed=0

  apt_install_packages "${POSTGRES_PACKAGES[@]}" || failed=1
  ensure_service_enabled_started postgresql || failed=1

  if configure_pgadmin_repository; then
    apt_install_packages pgadmin4-desktop || failed=1
  elif is_pkg_installed pgadmin4-desktop; then
    log_warn "pgAdmin repository setup failed, but pgAdmin desktop is already installed"
  elif command -v snap >/dev/null 2>&1 && snap list pgadmin4 >/dev/null 2>&1; then
    install_pgadmin_snap || failed=1
  else
    install_pgadmin_snap || failed=1
  fi

  install_dbeaver || failed=1

  if is_pkg_installed pgadmin4-desktop || (command -v snap >/dev/null 2>&1 && snap list pgadmin4 >/dev/null 2>&1) || command -v pgadmin4 >/dev/null 2>&1 || [[ -x /snap/bin/pgadmin4 ]]; then
    return "$failed"
  fi

  return 1
}

check_postgres_contrib() {
  if compgen -G "/usr/share/postgresql/*/extension/pgcrypto.control" >/dev/null || compgen -G "/usr/share/postgresql/*/extension/uuid-ossp.control" >/dev/null; then
    printf '  - [ok] PostgreSQL contrib extensions\n'
  else
    printf '  - [missing] PostgreSQL contrib extensions\n'
    MISSING_REQUIRED+=("PostgreSQL contrib extensions")
  fi
}

check_pgadmin() {
  if is_pkg_installed pgadmin4-desktop; then
    printf '  - [ok] pgAdmin 4 desktop\n'
  elif command -v snap >/dev/null 2>&1 && snap list pgadmin4 >/dev/null 2>&1; then
    printf '  - [ok] pgAdmin 4 snap\n'
  elif command -v pgadmin4 >/dev/null 2>&1 || [[ -x /snap/bin/pgadmin4 ]]; then
    printf '  - [ok] pgAdmin 4\n'
  else
    printf '  - [missing] pgAdmin 4\n'
    MISSING_REQUIRED+=("pgAdmin 4")
  fi
}

check_dbeaver() {
  if is_pkg_installed dbeaver-ce || command -v dbeaver >/dev/null 2>&1; then
    printf '  - [ok] DBeaver CE\n'
  else
    printf '  - [missing] DBeaver CE\n'
    MISSING_REQUIRED+=("DBeaver CE")
  fi
}

verify_postgres_pgadmin() {
  check_required_cmd "PostgreSQL client" psql
  check_required_pkg "PostgreSQL server" postgresql
  check_postgres_contrib
  check_required_pkg "PostgreSQL development files" libpq-dev
  check_pgadmin
  check_dbeaver
  check_service_status "postgresql" postgresql
}

register_group "postgres-pgadmin" "PostgreSQL, pgAdmin, and DBeaver" install_postgres_pgadmin verify_postgres_pgadmin

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_group_file_cli "postgres-pgadmin" "$@"
fi
