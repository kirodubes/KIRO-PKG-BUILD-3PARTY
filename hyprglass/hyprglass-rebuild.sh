#!/bin/bash
set -uo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://kiroproject.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
#   Purpose:
#   Run by the 90-hyprglass-rebuild pacman hook after hyprland or
#   hyprglass is installed or upgraded. When the installed plugin
#   was built for another Hyprland, it compiles the source shipped in
#   /usr/src/hyprglass against the Hyprland now on the system and
#   replaces the plugin. A failed build leaves the old plugin in place.
#
#   Why: a Hyprland plugin embeds the exact Hyprland commit and is
#   refused on any other build. Without this, the glass effect is off from
#   the day Arch updates Hyprland until the rebuilt package arrives.
#
#   Runs as root inside the pacman transaction: no set -e, no colors,
#   and it always exits 0 so it can never fail an update.
#
#####################################################################

NAME="hyprglass"
BUILT="hyprglass.so"
PLUGIN="/usr/lib/hyprland-plugins/hyprglass.so"
MAKE_ARGS=(HYPRGLASS_VERSION=@PKGVER@)

SRC="/usr/src/${NAME}"
VERSION_H="/usr/include/hyprland/src/version.h"
LOG="/var/log/kiro-hyprland-plugins/${NAME}.log"

commit="$(sed -n 's/^#define GIT_COMMIT_HASH *"\([0-9a-f]\{40\}\)".*/\1/p' "${VERSION_H}" 2>/dev/null)"
tag="$(sed -n 's/^#define GIT_TAG *"\(.*\)".*/\1/p' "${VERSION_H}" 2>/dev/null)"
[[ -n "${commit}" && -d "${SRC}" ]] || exit 0

# Already built for this Hyprland: the usual case, the rebuilt package came with the update.
grep -qaF "${commit}" "${PLUGIN}" 2>/dev/null && exit 0

for tool in g++ make pkg-config; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "${NAME}: not rebuilt for Hyprland ${tag}, ${tool} is missing"
        exit 0
    fi
done

work="$(mktemp -d)" || exit 0
trap 'rm -rf "${work}"' EXIT
cp -r "${SRC}" "${work}/src"
chown -R nobody: "${work}"
mkdir -p "$(dirname "${LOG}")"

echo "${NAME}: built for another Hyprland, compiling it for ${tag} (this takes a moment)"
if runuser -u nobody -- make -C "${work}/src" -j"$(nproc)" "${MAKE_ARGS[@]}" >"${LOG}" 2>&1 \
    && grep -qaF "${commit}" "${work}/src/${BUILT}" \
    && install -s -m755 "${work}/src/${BUILT}" "${PLUGIN}"; then
    echo "${NAME}: rebuilt for Hyprland ${tag}, log out and back in to load it"
else
    echo "${NAME}: could not be rebuilt for Hyprland ${tag} (log: ${LOG})"
    echo "${NAME}: it stays off until the updated package arrives, nothing else is affected"
fi

exit 0
