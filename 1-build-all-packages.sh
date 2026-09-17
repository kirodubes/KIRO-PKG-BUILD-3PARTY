#!/bin/bash
set -euo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://kiroproject.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
# Purpose:
#   Full repo pass: sync every AUR-backed package dir with its current
#   AUR tree, update the build chroot once, build only the packages that
#   actually changed upstream, then publish nemesis_repo.
#
#   Run with --check to sync and report what WOULD rebuild and why, then
#   stop. Nothing is built and nothing is pushed.
#
# Why:
#   The old version built blind: it never consulted upstream, and it ran
#   pacman -Syu inside the chroot once per package -- eighteen times per
#   full run. The chroot update is now hoisted to a single pass here, and
#   the upstream check lives in aur-sync.sh + build.sh.
#####################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

#####################################################################
# Colors
#####################################################################
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 6)"
    RESET="$(tput sgr0)"
else
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" RESET=""
fi

#####################################################################
# Logging
#####################################################################
log_section() {
    echo
    echo "${GREEN}############################################################################${RESET}"
    echo "$1"
    echo "${GREEN}############################################################################${RESET}"
    echo
}

log_info() {
    echo
    echo "${BLUE}############################################################################${RESET}"
    echo "$1"
    echo "${BLUE}############################################################################${RESET}"
    echo
}

log_warn() {
    echo
    echo "${YELLOW}############################################################################${RESET}"
    echo "$1"
    echo "${YELLOW}############################################################################${RESET}"
    echo
}

log_error() {
    echo
    echo "${RED}############################################################################${RESET}"
    echo "$1"
    echo "${RED}############################################################################${RESET}"
    echo
}

log_success() {
    echo
    echo "${GREEN}############################################################################${RESET}"
    echo "$1"
    echo "${GREEN}############################################################################${RESET}"
    echo
}

#####################################################################
# Error handling
#####################################################################
on_error() {
    local lineno="$1"
    local cmd="$2"
    echo
    echo "${RED}ERROR on line ${lineno}: ${cmd}${RESET}"
    echo
    sleep 10
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

#####################################################################
# Configuration
#####################################################################
CHROOT="${HOME}/Documents/chroot-archlinux"
CHECK_ONLY="false"
BUILT_PKGS=()
SKIPPED_PKGS=()
FAILED_BUILDS=()

# shellcheck source=packages.conf
source "${SCRIPT_DIR}/packages.conf"

#####################################################################
# Functions
#####################################################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) CHECK_ONLY="true" ;;
            *) log_error "Unknown option: $1
Usage: $(basename "$0") [--check]"; exit 1 ;;
        esac
        shift
    done
}

sync_from_aur() {
    log_section "Syncing package dirs from the AUR"
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        bash "${SCRIPT_DIR}/aur-sync.sh" --check
    else
        bash "${SCRIPT_DIR}/aur-sync.sh"
    fi
}

# Once per run, not once per package.
update_chroot() {
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        log_info "--check: skipping chroot update"
        return 0
    fi
    log_section "Updating chroot ${CHROOT} (once for this run)"
    arch-nspawn "${CHROOT}/root" pacman -Syu --noconfirm
}

build_all_packages() {
    local dirs total count name rc

    mapfile -t dirs < <(find "${SCRIPT_DIR}" -maxdepth 1 -mindepth 1 -type d \
        -not -name ".*" -not -name "patches" | sort)
    total="${#dirs[@]}"
    count=0

    log_section "Processing ${total} packages"

    for dir in "${dirs[@]}"; do
        count=$((count + 1))
        name="$(basename "${dir}")"

        log_info "Package ${count} of ${total}: ${name} (${PKG_CLASS[${name}]:-unclassified})"

        if [[ ! -f "${dir}/build.sh" ]]; then
            log_warn "No build script found for ${name} — skipping"
            echo "Error: ${name} has no build script" | tee -a /tmp/failed
            FAILED_BUILDS+=("${name} (no build.sh)")
            continue
        fi

        rc=0
        if [[ "${CHECK_ONLY}" == "true" ]]; then
            (cd "${dir}" && bash ./build.sh --check) || rc=$?
        else
            (cd "${dir}" && bash ./build.sh --no-chroot-update) || rc=$?
        fi

        if [[ "${rc}" -ne 0 ]]; then
            FAILED_BUILDS+=("${name}")
        fi
    done
}

publish_repo() {
    if [[ "${CHECK_ONLY}" == "true" ]]; then
        log_warn "--check: NOT publishing (up.sh commits and pushes the live repo)"
        return 0
    fi
    log_section "Publishing nemesis_repo"
    bash "${HOME}/EDU/nemesis_repo/up.sh"
}

report() {
    log_section "Run summary"

    if [[ "${#FAILED_BUILDS[@]}" -gt 0 ]]; then
        echo "${RED}Failed:${RESET}"
        printf '  %s\n' "${FAILED_BUILDS[@]}"
        echo
    fi

    echo "See the per-package output above for what rebuilt and why."
    echo "Details of anything flagged: /tmp/failed"
}

#####################################################################
# Main
#####################################################################
main() {
    parse_args "$@"

    : > /tmp/failed

    sync_from_aur
    update_chroot
    build_all_packages
    publish_repo
    report

    log_success "$(basename "$0") done"
}

main "$@"
