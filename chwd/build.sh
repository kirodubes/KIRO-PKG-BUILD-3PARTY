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
#   Per-package build driver. Decides whether this package actually
#   needs rebuilding, and if so builds it in the clean chroot and copies
#   the result into ~/EDU/nemesis_repo/x86_64/.
#
#   The rebuild decision depends on the package class in packages.conf:
#
#     aur-fixed  pkgver/pkgrel/epoch changed since the last good build
#     aur-vcs    upstream git HEAD moved since the last good build,
#                read live with git ls-remote
#     local      pkgver/pkgrel changed locally (in-house packages)
#
# Why:
#   The previous version compared the PKGBUILD against .previous-version,
#   which only ever detects edits YOU made. VCS packages therefore never
#   rebuilt: makepkg's pkgver() rewrites the version in the /tmp build
#   copy, never in the source dir, so the literal it compared was frozen
#   forever. For a -git package it is the upstream push that decides, and
#   the AUR's own pkgver is meaningless because it is frozen too.
#####################################################################

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

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
PKGNAME="$(basename "${SCRIPT_DIR}")"
STATE_FILE="${SCRIPT_DIR}/.build-state"
CHROOT="${HOME}/Documents/chroot-archlinux"
DESTINY="${HOME}/EDU/nemesis_repo/x86_64/"
UPDATE_CHROOT="true"
CHECK_ONLY="false"
BUILD_NEEDED="false"
BUILD_REASON=""
NEW_UPSTREAM_COMMIT=""

if [[ -f "${REPO_DIR}/packages.conf" ]]; then
    # shellcheck source=packages.conf
    source "${REPO_DIR}/packages.conf"
else
    declare -A PKG_CLASS=() PKG_UPSTREAM=() PKG_UPSTREAM_REF=()
fi

PKG_TYPE="${PKG_CLASS[${PKGNAME}]:-local}"

#####################################################################
# Functions
#####################################################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-chroot-update) UPDATE_CHROOT="false" ;;
            --check)            CHECK_ONLY="true" ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
        shift
    done
}

read_state() {
    local key="$1"
    [[ -f "${STATE_FILE}" ]] || return 0
    grep -m1 "^${key}=" "${STATE_FILE}" 2>/dev/null | cut -d= -f2- || true
}

pkgbuild_field() {
    local key="$1"
    grep -m1 -E "^${key}=" "${SCRIPT_DIR}/PKGBUILD" 2>/dev/null | cut -d= -f2- | tr -d "'\"" || true
}

# Only in-house date-versioned packages are auto-bumped. Anything that
# comes from the AUR has its version owned by the AUR.
bump_version() {
    local old_pkgver old_pkgrel new_pkgver new_pkgrel

    if [[ "${PKG_TYPE}" != "local" ]]; then
        log_info "${PKGNAME}: version owned by the AUR (class: ${PKG_TYPE}) — no bump"
        return 0
    fi

    old_pkgver="$(pkgbuild_field pkgver)"
    old_pkgrel="$(pkgbuild_field pkgrel)"

    if [[ ! "${old_pkgver}" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
        log_info "Upstream-versioned package (pkgver=${old_pkgver}) — skipping bump"
        return 0
    fi

    new_pkgver="$(date +%y.%m)"
    if [[ "${new_pkgver}" != "${old_pkgver}" ]]; then
        new_pkgrel="01"
    else
        new_pkgrel="$(printf '%02d' $((10#${old_pkgrel} + 1)))"
    fi

    sed -i "s/^pkgver=.*/pkgver=${new_pkgver}/" "${SCRIPT_DIR}/PKGBUILD"
    sed -i "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" "${SCRIPT_DIR}/PKGBUILD"

    log_info "Updated '${PKGNAME}':
  pkgver: ${old_pkgver} → ${new_pkgver}
  pkgrel: ${old_pkgrel} → ${new_pkgrel}"
}

# For a -git package the PKGBUILD version is a frozen placeholder, so the
# only honest signal is whether upstream has pushed since the last build.
check_vcs_upstream() {
    local url ref old new

    url="${PKG_UPSTREAM[${PKGNAME}]:-}"
    ref="${PKG_UPSTREAM_REF[${PKGNAME}]:-HEAD}"

    if [[ -z "${url}" ]]; then
        log_error "${PKGNAME} is class aur-vcs but has no upstream URL in packages.conf"
        exit 1
    fi

    new="$(git ls-remote "${url}" "${ref}" 2>/dev/null | awk '{print $1}' | head -1)"
    if [[ -z "${new}" ]]; then
        log_error "${PKGNAME}: cannot reach upstream ${url} (ref ${ref})"
        exit 1
    fi

    old="$(read_state upstream_commit)"
    NEW_UPSTREAM_COMMIT="${new}"

    log_info "$(printf 'Package:  %s (aur-vcs)\nUpstream: %s\nPrevious: %s\nCurrent:  %s' \
        "${PKGNAME}" "${url}" "${old:-<none>}" "${new}")"

    if [[ "${new}" != "${old}" ]]; then
        BUILD_NEEDED="true"
        BUILD_REASON="upstream pushed ${old:0:7}..${new:0:7}"
    fi
}

check_version_fields() {
    local pkgver pkgrel epoch oldver oldrel oldepoch

    pkgver="$(pkgbuild_field pkgver)"
    pkgrel="$(pkgbuild_field pkgrel)"
    epoch="$(pkgbuild_field epoch)"

    oldver="$(read_state pkgver)"
    oldrel="$(read_state pkgrel)"
    oldepoch="$(read_state epoch)"

    log_info "$(printf 'Package:  %s (%s)\nPrevious: pkgver=%s pkgrel=%s epoch=%s\nCurrent:  pkgver=%s pkgrel=%s epoch=%s' \
        "${PKGNAME}" "${PKG_TYPE}" \
        "${oldver:-<none>}" "${oldrel:-<none>}" "${oldepoch:-}" \
        "${pkgver}" "${pkgrel}" "${epoch}")"

    if [[ "${pkgver}" != "${oldver}" || "${pkgrel}" != "${oldrel}" || "${epoch}" != "${oldepoch}" ]]; then
        BUILD_NEEDED="true"
        BUILD_REASON="version ${oldver:-<none>}-${oldrel:-<none>} → ${pkgver}-${pkgrel}"
    fi
}

check_version() {
    if [[ "${PKG_TYPE}" == "aur-vcs" ]]; then
        check_vcs_upstream
    else
        check_version_fields
    fi
}

update_chroot() {
    [[ "${UPDATE_CHROOT}" == "true" ]] || return 0
    log_section "Updating chroot ${CHROOT}"
    arch-nspawn "${CHROOT}/root" pacman -Syu --noconfirm
}

# State is written only after a successful build, so a failed build is
# retried on the next run instead of being recorded as done.
write_state() {
    {
        printf 'pkgver=%s\n' "$(pkgbuild_field pkgver)"
        printf 'pkgrel=%s\n' "$(pkgbuild_field pkgrel)"
        printf 'epoch=%s\n'  "$(pkgbuild_field epoch)"
        [[ -n "${NEW_UPSTREAM_COMMIT}" ]] && printf 'upstream_commit=%s\n' "${NEW_UPSTREAM_COMMIT}"
        printf 'built=%s\n' "$(date +%Y-%m-%d)"
    } > "${STATE_FILE}"
}

build_package() {
    local success="false"

    [[ -d /tmp/tempbuild ]] && rm -rf /tmp/tempbuild
    mkdir /tmp/tempbuild
    cp -r "${SCRIPT_DIR}/"* /tmp/tempbuild/

    log_section "Building ${PKGNAME} in CHROOT ${CHROOT}"
    if (cd /tmp/tempbuild && makechrootpkg -c -r "${CHROOT}"); then
        success="true"
    fi

    if [[ "${success}" != "true" ]]; then
        log_error "Build FAILED for ${PKGNAME} — state not updated, will retry next run"
        echo "${PKGNAME}: build failed" >> /tmp/failed
        return 1
    fi

    # Overwrite rather than cp -n: we only get here because a rebuild was
    # needed, and a VCS package can legitimately rebuild to the SAME filename.
    # Refusing the copy there would leave the stale binary in the repo while
    # the state file recorded a successful build.
    log_section "Copying packages to ${DESTINY}"
    local built
    for built in /tmp/tempbuild/*"${PKGNAME}"*pkg.tar.zst; do
        [[ -e "${built}" ]] || continue
        if [[ -e "${DESTINY}/$(basename "${built}")" ]]; then
            log_warn "Replacing existing $(basename "${built}") in the repo"
        fi
        cp -fv "${built}" "${DESTINY}"
    done

    local file_count
    file_count=$(find "${DESTINY}" -maxdepth 1 -name "${PKGNAME}*" -print | wc -l)
    if [[ "${file_count}" -gt 2 ]]; then
        printf "%s\n" "${PKGNAME}" | tee -a /tmp/installed
        find "${DESTINY}" -maxdepth 1 -name "${PKGNAME}*" -exec basename {} \; | tee -a /tmp/installed
    fi

    log_section "Cleaning up"
    find "${SCRIPT_DIR}" -maxdepth 1 \( -name "*.log" -o -name "*.deb" -o -name "*.tar.gz" \) -delete

    write_state
    log_success "Build done for ${PKGNAME}"
}

#####################################################################
# Main
#####################################################################
main() {
    parse_args "$@"
    [[ "${CHECK_ONLY}" == "true" ]] || bump_version
    check_version

    if [[ "${BUILD_NEEDED}" == "false" ]]; then
        log_warn "${PKGNAME}: up to date — skipping build"
        exit 0
    fi

    log_info "${PKGNAME}: REBUILD NEEDED (${BUILD_REASON})"

    if [[ "${CHECK_ONLY}" == "true" ]]; then
        exit 0
    fi

    update_chroot
    build_package

    log_success "$(basename "$0") done"
}

main "$@"
