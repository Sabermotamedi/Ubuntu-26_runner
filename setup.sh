#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
load_groups_from_dir "$SCRIPT_DIR/groups"

show_help() {
  cat <<'USAGE'
Usage:
  sudo ./setup.sh
  sudo ./setup.sh --list
  sudo ./setup.sh --only docker,node,python
  sudo ./setup.sh --skip editors,ai-tools
  ./setup.sh --verify
  ./setup.sh docker node

Options:
  --list              Show available setup groups
  --only GROUPS       Run only comma-separated groups
  --skip GROUPS       Run all except comma-separated groups
  --verify            Only verify selected groups, do not install
  -h, --help          Show this help

Examples:
  sudo ./setup.sh --only postgres-pgadmin
  sudo ./setup.sh --only docker,node,python
  sudo ./setup.sh --skip cleanup
  ./setup.sh --verify --only editors,ai-tools

Individual group scripts can also run directly:
  sudo ./groups/70-postgres-pgadmin.sh
  ./groups/70-postgres-pgadmin.sh --verify
USAGE
}

ONLY_GROUPS=()
SKIP_GROUPS=()
POSITIONAL_GROUPS=()
SELECTED_GROUPS=()
VERIFY_ONLY=0
LIST_ONLY=0

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --list)
      LIST_ONLY=1
      shift
      ;;
    --only)
      if [[ -z "${2:-}" ]]; then
        log_error "--only requires a comma-separated group list"
        exit 2
      fi
      split_group_list "$2" ONLY_GROUPS
      shift 2
      ;;
    --only=*)
      split_group_list "${1#--only=}" ONLY_GROUPS
      shift
      ;;
    --skip)
      if [[ -z "${2:-}" ]]; then
        log_error "--skip requires a comma-separated group list"
        exit 2
      fi
      split_group_list "$2" SKIP_GROUPS
      shift 2
      ;;
    --skip=*)
      split_group_list "${1#--skip=}" SKIP_GROUPS
      shift
      ;;
    --verify)
      VERIFY_ONLY=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    --)
      shift
      while [[ "$#" -gt 0 ]]; do
        POSITIONAL_GROUPS+=("$1")
        shift
      done
      ;;
    -* )
      log_error "Unknown option: $1"
      printf '\n'
      show_help
      exit 2
      ;;
    *)
      POSITIONAL_GROUPS+=("$1")
      shift
      ;;
  esac
done

if [[ "$LIST_ONLY" -eq 1 ]]; then
  list_groups
  exit 0
fi

if [[ "${#ONLY_GROUPS[@]}" -eq 0 && "${#POSITIONAL_GROUPS[@]}" -gt 0 ]]; then
  ONLY_GROUPS=("${POSITIONAL_GROUPS[@]}")
elif [[ "${#POSITIONAL_GROUPS[@]}" -gt 0 ]]; then
  log_error "Use either --only or positional groups, not both."
  exit 2
fi

validate_group_names "${ONLY_GROUPS[@]}" "${SKIP_GROUPS[@]}"
select_groups SELECTED_GROUPS ONLY_GROUPS SKIP_GROUPS

if [[ "${#SELECTED_GROUPS[@]}" -eq 0 ]]; then
  log_error "No setup groups selected."
  exit 2
fi

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  check_ubuntu_version
  if verify_selected_groups "${SELECTED_GROUPS[@]}"; then
    log_section "Verification complete"
    log_info "All selected groups passed verification."
    exit 0
  fi

  log_section "Verification completed with attention needed"
  log_info "Review the report above."
  exit 1
fi

bootstrap_setup
run_selected_group_installs "${SELECTED_GROUPS[@]}"

if verify_selected_groups "${SELECTED_GROUPS[@]}"; then
  log_section "Setup complete"
  log_info "All selected groups are installed."
  log_info "If docker group membership changed, log out and log back in."
  exit 0
fi

log_section "Setup completed with attention needed"
log_info "The script continued instead of panicking, but some required items are missing."
log_info "Review the report above, fix the listed problem, then run this script again."
exit 1
