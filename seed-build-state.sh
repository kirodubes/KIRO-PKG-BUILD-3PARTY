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
#   One-time bootstrap for the .build-state files, derived from the
#   packages already sitting in ~/EDU/nemesis_repo/x86_64/.
#
#   For a fixed-version package the artifact version is compared with
#   the PKGBUILD version. For a -git package the commit embedded in the
#   artifact pkgver (the .g<sha> suffix makepkg writes) is compared with
#   the current upstream HEAD. A package is seeded as "already built"
#   only when they match; anything that does not match is deliberately
#   left unseeded so the next run rebuilds it.
#
# Why:
#   The rebuild check is a comparison against the last good build, and
#   without this the very first run has nothing to compare against and
#   would rebuild all eighteen packages from scratch -- which is exactly
#   the blind rebuilding the new flow exists to stop.
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
DESTINY="${HOME}/EDU/nemesis_repo/x86_64"
SEEDED=()
UNSEEDED=()

# shellcheck source=packages.conf
source "${SCRIPT_DIR}/packages.conf"

#####################################################################
# Functions
#####################################################################
pkgbuild_field() {
    local pkg="$1" key="$2"
    grep -m1 -E "^${key}=" "${SCRIPT_DIR}/${pkg}/PKGBUILD" 2>/dev/null | cut -d= -f2- | tr -d "'\"" || true
}

# Newest artifact for this package. The trailing -pkgrel-arch shape is
# what distinguishes "pkg-1.2-1-any" from a different package that merely
# starts with the same string, so match on that rather than on the
# version, whose first character varies (1.2, r2230, v1.0.1, 1:140...).
find_artifact() {
    local pkg="$1" file base rest

    while IFS= read -r file; do
        base="$(basename "${file}" .pkg.tar.zst)"
        rest="${base#"${pkg}"-}"
        [[ "${rest}" =~ ^[^-]+-[0-9]+-(x86_64|any|i686)$ ]] && printf '%s\n' "${file}"
    done < <(find "${DESTINY}" -maxdepth 1 -name "${pkg}-*.pkg.tar.zst" 2>/dev/null | sort -V)
}

# pkgname-<epoch:>pkgver-pkgrel-arch.pkg.tar.zst -> "<pkgver> <pkgrel>"
artifact_version() {
    local pkg="$1" file base rest
    file="$(find_artifact "${pkg}" | tail -1)"
    [[ -n "${file}" ]] || return 1

    base="$(basename "${file}" .pkg.tar.zst)"
    rest="${base#"${pkg}"-}"
    rest="${rest%-*}"                 # drop arch
    printf '%s %s\n' "${rest%-*}" "${rest##*-}"
}

seed_fixed() {
    local pkg="$1" av ap pv pr epoch artver

    artver="$(artifact_version "${pkg}")" || { UNSEEDED+=("${pkg} (no artifact)"); return 0; }
    av="${artver% *}"
    ap="${artver#* }"
    av="${av#*:}"                     # strip epoch prefix

    pv="$(pkgbuild_field "${pkg}" pkgver)"
    pr="$(pkgbuild_field "${pkg}" pkgrel)"
    epoch="$(pkgbuild_field "${pkg}" epoch)"

    if [[ "${av}" == "${pv}" && "${ap}" == "${pr}" ]]; then
        {
            printf 'pkgver=%s\n' "${pv}"
            printf 'pkgrel=%s\n' "${pr}"
            printf 'epoch=%s\n'  "${epoch}"
            printf 'built=%s\n'  "seeded-from-artifact"
        } > "${SCRIPT_DIR}/${pkg}/.build-state"
        SEEDED+=("${pkg} ${pv}-${pr}")
    else
        UNSEEDED+=("${pkg} (built ${av}-${ap}, recipe ${pv}-${pr})")
    fi
}

seed_vcs() {
    local pkg="$1" url ref head artver shortsha

    url="${PKG_UPSTREAM[${pkg}]:-}"
    ref="${PKG_UPSTREAM_REF[${pkg}]:-HEAD}"
    [[ -n "${url}" ]] || { UNSEEDED+=("${pkg} (no upstream)"); return 0; }

    artver="$(artifact_version "${pkg}")" || { UNSEEDED+=("${pkg} (no artifact)"); return 0; }
    artver="${artver% *}"

    # makepkg writes ...r<count>.g<sha> or ...r<count>.<sha>
    shortsha="$(grep -oE '\.g?[0-9a-f]{7,}$' <<< "${artver}" | tr -d '.g' || true)"
    if [[ -z "${shortsha}" ]]; then
        UNSEEDED+=("${pkg} (artifact ${artver} embeds no commit)")
        return 0
    fi

    head="$(git ls-remote "${url}" "${ref}" 2>/dev/null | awk '{print $1}' | head -1)"
    if [[ -z "${head}" ]]; then
        UNSEEDED+=("${pkg} (upstream unreachable)")
        return 0
    fi

    if [[ "${head}" == "${shortsha}"* ]]; then
        {
            printf 'pkgver=%s\n' "$(pkgbuild_field "${pkg}" pkgver)"
            printf 'pkgrel=%s\n' "$(pkgbuild_field "${pkg}" pkgrel)"
            printf 'epoch=%s\n'  "$(pkgbuild_field "${pkg}" epoch)"
            printf 'upstream_commit=%s\n' "${head}"
            printf 'built=%s\n' "seeded-from-artifact"
        } > "${SCRIPT_DIR}/${pkg}/.build-state"
        SEEDED+=("${pkg} @ ${shortsha}")
    else
        UNSEEDED+=("${pkg} (built @${shortsha}, upstream @${head:0:7})")
    fi
}

seed_all() {
    local pkg class

    log_section "Seeding .build-state from ${DESTINY}"

    for pkg in $(printf '%s\n' "${!PKG_CLASS[@]}" | sort); do
        [[ -d "${SCRIPT_DIR}/${pkg}" ]] || continue
        class="${PKG_CLASS[${pkg}]}"

        if [[ "${class}" == "aur-vcs" ]]; then
            seed_vcs "${pkg}"
        else
            seed_fixed "${pkg}"
        fi
    done
}

report() {
    log_section "Seed summary"

    echo "${GREEN}Seeded as already built (will NOT rebuild):${RESET}"
    if [[ "${#SEEDED[@]}" -gt 0 ]]; then
        printf '  %s\n' "${SEEDED[@]}"
    else
        echo "  none"
    fi

    echo
    echo "${YELLOW}Left unseeded (WILL rebuild on the next run):${RESET}"
    if [[ "${#UNSEEDED[@]}" -gt 0 ]]; then
        printf '  %s\n' "${UNSEEDED[@]}"
    else
        echo "  none"
    fi
}

#####################################################################
# Main
#####################################################################
main() {
    seed_all
    report

    log_success "$(basename "$0") done"
}

main "$@"
