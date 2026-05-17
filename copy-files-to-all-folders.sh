#!/bin/bash
set -euo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://www.erikdubois.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
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
# Functions
#####################################################################
total_dirs=0
total_copies=0

copy_script() {
    local filename="$1"
    local source="${SCRIPT_DIR}/${filename}"
    local count=0

    if [[ ! -f "${source}" ]]; then
        log_error "${filename} not found in ${SCRIPT_DIR}"
        exit 1
    fi

    log_section "Copying ${filename} to all subdirectories"

    while IFS= read -r -d '' dir; do
        cp -v "${source}" "${dir}/${filename}"
        count=$(( count + 1 ))
    done < <(find "${SCRIPT_DIR}" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -print0 | sort -z)

    total_dirs=$count
    total_copies=$(( total_copies + count ))
}

#####################################################################
# Main
#####################################################################
main() {
    local repo_name
    repo_name="$(basename "${PWD}")"

    log_info "Detected repo: ${repo_name}"

    if [[ "${repo_name,,}" == *pkg*build* || "${repo_name,,}" == *pkg-build* ]]; then
        copy_script "build.sh"
    else
        copy_script "setup.sh"
        copy_script "up.sh"
    fi

    log_info "Directories: ${total_dirs} | Files copied: ${total_copies}"
    log_success "$(basename "$0") done"
}

main "$@"
