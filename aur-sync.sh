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
#   Bring every AUR-backed package directory in this repo up to date
#   with its current AUR tree. Each AUR repo is cloned once into
#   ~/.cache/kiro-aur/<pkg> and then rsync'ed into the package dir, so
#   companion files (.install scripts, pacman hooks, .json, patches)
#   travel with the PKGBUILD instead of drifting out of sync.
#
#   Packages carrying a Kiro local delta declare it in packages.conf as
#   an explicit patch under patches/<pkg>/. The patch is replayed on top
#   of the fresh AUR tree and -- if it no longer applies -- the package
#   is reported for manual attention rather than shipped unpatched.
#
#   The delta list is deliberately explicit rather than auto-detected by
#   diffing against the AUR: for a package that is merely STALE, that
#   diff is the staleness itself, and replaying it would revert the very
#   update the sync just pulled in.
#
#   Run with --check to report what would change without writing.
#
# Why:
#   Nothing in the old flow ever looked at upstream. Fixed-version
#   packages went stale in place (lastpass sat 4 releases behind) and
#   VCS packages never rebuilt, because the local PKGBUILD literals
#   they were compared against never changed.
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
CACHE_DIR="${HOME}/.cache/kiro-aur"
AUR_BASE="https://aur.archlinux.org"
CHECK_ONLY="false"
FAILED_PKGS=()
CHANGED_PKGS=()

# shellcheck source=packages.conf
source "${SCRIPT_DIR}/packages.conf"

#####################################################################
# Functions
#####################################################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) CHECK_ONLY="true" ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done
}

# Every package dir on disk must be classified in packages.conf, so a new
# folder cannot slip through the sync unnoticed.
validate_classification() {
    local dir name missing=()

    for dir in "${SCRIPT_DIR}"/*/; do
        name="$(basename "${dir}")"
        [[ -f "${dir}/PKGBUILD" ]] || continue
        [[ -v PKG_CLASS[${name}] ]] || missing+=("${name}")
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        log_error "Unclassified package dirs (add them to packages.conf):
$(printf '  %s\n' "${missing[@]}")"
        exit 1
    fi
}

fetch_aur_tree() {
    local pkg="$1"
    local cache="${CACHE_DIR}/${pkg}"

    if [[ -d "${cache}/.git" ]]; then
        git -C "${cache}" fetch --quiet origin
        git -C "${cache}" reset --quiet --hard origin/HEAD
    else
        rm -rf "${cache}"
        git clone --quiet "${AUR_BASE}/${pkg}.git" "${cache}"
    fi
}

# Kiro deltas are declared in packages.conf, never inferred. Each is a
# -p1 patch under patches/<pkg>/ applied after the AUR tree lands.
apply_kiro_patches() {
    local pkg="$1"
    local dry="$2"
    local dir="${SCRIPT_DIR}/patches/${pkg}"
    local target="${SCRIPT_DIR}/${pkg}"
    local p args

    [[ -d "${dir}" ]] || return 0

    args=(-p1 --forward -d "${target}")
    [[ "${dry}" == "true" ]] && args+=(--dry-run)

    for p in "${dir}"/*.patch; do
        [[ -e "${p}" ]] || continue
        if ! patch "${args[@]}" < "${p}" >/dev/null 2>&1; then
            log_error "${pkg}: Kiro patch does not apply: $(basename "${p}")
The AUR tree has moved under it. Resolve by hand, then update the patch."
            return 1
        fi
    done
}

sync_package() {
    local pkg="$1"
    local cache="${CACHE_DIR}/${pkg}"
    local target="${SCRIPT_DIR}/${pkg}"
    local before="" after=""

    fetch_aur_tree "${pkg}"

    [[ -f "${target}/PKGBUILD" ]] && before="$(sha256sum "${target}/PKGBUILD" | cut -d' ' -f1)"

    if [[ "${CHECK_ONLY}" == "true" ]]; then
        # Verify the declared patches still apply to the incoming tree,
        # without touching the package dir.
        if ! apply_kiro_patches_against_cache "${pkg}"; then
            FAILED_PKGS+=("${pkg}")
            return 0
        fi
        if ! diff -q "${cache}/PKGBUILD" "${target}/PKGBUILD" >/dev/null 2>&1; then
            log_info "${pkg}: AUR tree differs — would sync"
            CHANGED_PKGS+=("${pkg}")
        fi
        return 0
    fi

    # build.sh and our state files are ours, not AUR's -- protect them.
    rsync -a --delete \
        --exclude=.git \
        --exclude=build.sh \
        --exclude=.build-state \
        --exclude=.aur-commit \
        --exclude=.current-version \
        --exclude=.previous-version \
        "${cache}/" "${target}/"

    if ! apply_kiro_patches "${pkg}" "false"; then
        FAILED_PKGS+=("${pkg}")
        echo "${pkg}: Kiro patch failed to apply" >> /tmp/failed
        return 0
    fi

    record_aur_commit "${pkg}"

    after="$(sha256sum "${target}/PKGBUILD" | cut -d' ' -f1)"
    [[ "${before}" != "${after}" ]] && CHANGED_PKGS+=("${pkg}")
    return 0
}

# --check variant: test the patches against the pristine cache copy so the
# real package dir is never written to.
apply_kiro_patches_against_cache() {
    local pkg="$1"
    local dir="${SCRIPT_DIR}/patches/${pkg}"
    local p

    [[ -d "${dir}" ]] || return 0

    for p in "${dir}"/*.patch; do
        [[ -e "${p}" ]] || continue
        if ! patch -p1 --forward --dry-run -d "${CACHE_DIR}/${pkg}" < "${p}" >/dev/null 2>&1; then
            log_error "${pkg}: Kiro patch would not apply: $(basename "${p}")"
            return 1
        fi
    done
}

record_aur_commit() {
    local pkg="$1"
    local cache="${CACHE_DIR}/${pkg}"
    local sha

    sha="$(git -C "${cache}" rev-parse HEAD)"
    printf 'aur_commit=%s\n' "${sha}" > "${SCRIPT_DIR}/${pkg}/.aur-commit"
}

sync_all() {
    local pkg class total count

    total=0
    for pkg in "${!PKG_CLASS[@]}"; do
        [[ "${PKG_CLASS[${pkg}]}" == "local" ]] && continue
        total=$((total + 1))
    done

    log_section "Syncing ${total} AUR packages into $(basename "${SCRIPT_DIR}")"

    count=0
    for pkg in $(printf '%s\n' "${!PKG_CLASS[@]}" | sort); do
        class="${PKG_CLASS[${pkg}]}"

        if [[ "${class}" == "local" ]]; then
            log_info "${pkg}: not on the AUR (class: local) — skipping sync"
            continue
        fi

        if [[ ! -d "${SCRIPT_DIR}/${pkg}" ]]; then
            log_error "${pkg}: listed in packages.conf but the directory is missing"
            FAILED_PKGS+=("${pkg}")
            continue
        fi

        count=$((count + 1))
        log_info "Package ${count} of ${total}: ${pkg} (${class})"
        sync_package "${pkg}"
    done
}

report() {
    log_section "AUR sync summary"

    if [[ "${#CHANGED_PKGS[@]}" -gt 0 ]]; then
        echo "${GREEN}Synced:${RESET}"
        printf '  %s\n' "${CHANGED_PKGS[@]}"
    else
        echo "Nothing synced."
    fi

    if [[ "${#FAILED_PKGS[@]}" -gt 0 ]]; then
        echo
        echo "${RED}Needs manual attention:${RESET}"
        printf '  %s\n' "${FAILED_PKGS[@]}"
        return 1
    fi
}

#####################################################################
# Main
#####################################################################
main() {
    parse_args "$@"
    mkdir -p "${CACHE_DIR}"
    validate_classification
    sync_all
    report

    log_success "$(basename "$0") done"
}

main "$@"
