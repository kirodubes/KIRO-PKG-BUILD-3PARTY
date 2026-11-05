#!/bin/bash
set -euo pipefail
#####################################################################
# Author    : Erik Dubois
# Website   : https://kiroproject.be
#####################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
#   Purpose:
#   - Sync a private copy of the pacman databases (no root, the system
#     is never touched) and check every trigger in rebuild-triggers.conf.
#   - When Arch ships a trigger update that breaks packages we built
#     (Hyprland -> the plugins, libalpm -> pamac, Qt -> calamares, ...),
#     record a pending alert, email it once, and show a desktop
#     notification with a Seen button.
#   - A pending alert is shown again on every run (1 min after login,
#     then every 30 min) until Seen is clicked.
#   - Changes nothing in any package; the rebuild stays manual.
#
#   Why: users wait for these rebuilds while Erik is away from the PC,
#   so the update has to reach him the moment it lands, and a missed
#   notification must come back. Run by systemd/kiro-rebuild-watch.timer.
#
#   Usage: rebuild-watch.sh            check + mail + notify
#          rebuild-watch.sh --status   list pending alerts
#          rebuild-watch.sh --test     fake alert through mail + notification
#          rebuild-watch.sh --ack ID   mark an alert as seen by hand
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
    echo "${RED}ERROR on line $1: $2${RESET}"
    sleep 10
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

#####################################################################
# Functions
#####################################################################
SELF="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
CONF="${SCRIPT_DIR}/rebuild-triggers.conf"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/kiro-rebuild-watch"
SEEN="${STATE_DIR}/seen"
PENDING="${STATE_DIR}/pending"
ACKED="${STATE_DIR}/acked"
DB="${XDG_CACHE_HOME:-$HOME/.cache}/kiro-rebuild-watch/db"
MAIL_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-rebuild-watch/mail.conf"

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Value of KEY in an alert file (KEY=value lines).
alert_get() {
    sed -n "s/^$2=//p" "$1" | head -n1
}

sync_db() {
    log_section "Syncing a private pacman database in ${DB}"
    mkdir -p "$DB"
    [[ -L "${DB}/local" ]] || ln -s /var/lib/pacman/local "${DB}/local"
    fakeroot -- pacman -Sy --dbpath "$DB" --logfile /dev/null >/dev/null
}

# Arch's own package info: core first, then extra (never a Kiro/third-party repo).
pkg_info() {
    pacman -Si --dbpath "$DB" "core/$1" 2>/dev/null || pacman -Si --dbpath "$DB" "extra/$1" 2>/dev/null
}

info_field() {
    sed -n "s/^$1 *: //p" <<<"$2" | head -n1
}

minor_of() {
    sed -E 's/^([0-9]+:)?([0-9]+)(\.([0-9]+))?.*/\2.\4/' <<<"$1"
}

# What has to change for the trigger to count, per mode.
fingerprint() {
    local mode="$1" ver="$2" info="$3" sonames
    case "$mode" in
        version) printf '%s' "$ver" ;;
        minor) minor_of "$ver" ;;
        soname)
            sonames="$(info_field Provides "$info" | tr -s ' ' '\n' | grep -E '^lib.*\.so=' | sort | paste -sd' ' - || true)"
            if [[ -n "$sonames" ]]; then
                printf '%s' "$sonames"
            else
                minor_of "$ver"
            fi
            ;;
        *) return 1 ;;
    esac
}

create_alert() {
    local trigger="$1" old="$2" new="$3" rebuild="$4" hint="$5" change="${6:-}" id
    id="$(tr -c 'A-Za-z0-9._-' '-' <<<"${trigger}-${new}" | sed 's/-*$//')"
    mkdir -p "$PENDING"
    {
        echo "trigger=${trigger}"
        echo "old=${old}"
        echo "new=${new}"
        echo "rebuild=${rebuild}"
        echo "hint=${hint}"
        echo "change=${change}"
        echo "detected=$(date '+%Y-%m-%d %H:%M')"
        echo "mailed=no"
    } >"${PENDING}/${id}"
    log_warn "${trigger} ${old} -> ${new}: time to build ${CYAN}${rebuild}${RESET}"
}

check_triggers() {
    local first_run=false line trigger mode rebuild hint info ver fp old_line old_fp old_ver tmp
    [[ -f "$SEEN" ]] || first_run=true
    tmp="$(mktemp "${STATE_DIR}/seen.XXXXXX")"
    log_section "Checking $(grep -cvE '^[[:space:]]*(#|$)' "$CONF") triggers"
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        IFS='|' read -r trigger mode rebuild hint <<<"$line"
        trigger="$(trim "$trigger")" mode="$(trim "$mode")" rebuild="$(trim "$rebuild")" hint="$(trim "$hint")"
        old_line="$(grep -m1 -P "^\Q${trigger}\E\t" "$SEEN" 2>/dev/null || true)"
        if ! info="$(pkg_info "$trigger")"; then
            log_warn "${trigger} not found in core or extra -- check rebuild-triggers.conf"
            [[ -n "$old_line" ]] && echo "$old_line" >>"$tmp"
            continue
        fi
        ver="$(info_field Version "$info")"
        ver="${ver%-*}"
        fp="$(fingerprint "$mode" "$ver" "$info")"
        if [[ -n "$old_line" ]] && ! $first_run; then
            old_fp="$(cut -f2 <<<"$old_line")"
            old_ver="$(cut -f3 <<<"$old_line")"
            if [[ "$old_fp" != "$fp" ]]; then
                # A soname bump can come without a version change, so show what moved.
                if [[ "$mode" == "soname" && "$old_fp" == lib* ]]; then
                    create_alert "$trigger" "$old_ver" "$ver" "$rebuild" "$hint" "${old_fp} -> ${fp}"
                else
                    create_alert "$trigger" "$old_ver" "$ver" "$rebuild" "$hint"
                fi
            else
                echo "${trigger} ${ver}: unchanged"
            fi
        else
            echo "${trigger} ${ver}: recorded"
        fi
        printf '%s\t%s\t%s\n' "$trigger" "$fp" "$ver" >>"$tmp"
    done <"$CONF"
    mv "$tmp" "$SEEN"
    $first_run && log_info "First run: current versions recorded, alerts start from the next Arch update"
    return 0
}

send_mail() {
    local file="$1" trigger old new rebuild hint change subject msg
    trigger="$(alert_get "$file" trigger)" old="$(alert_get "$file" old)" new="$(alert_get "$file" new)"
    rebuild="$(alert_get "$file" rebuild)" hint="$(alert_get "$file" hint)"
    change="$(alert_get "$file" change)"
    # Own 0600 file in ~/.config; holds MAIL_TO, SMTP_USER, SMTP_PASS (Gmail app password).
    # shellcheck source=/dev/null
    source "$MAIL_CONF"
    if [[ -z "${MAIL_TO:-}" || -z "${SMTP_USER:-}" || -z "${SMTP_PASS:-}" ]]; then
        log_warn "${MAIL_CONF} is incomplete -- desktop notification only"
        return 0
    fi
    subject="Kiro rebuild: ${trigger} ${old} -> ${new} - build ${rebuild}"
    msg="$(mktemp)"
    {
        echo "From: Kiro rebuild watch <${MAIL_FROM:-$SMTP_USER}>"
        echo "To: ${MAIL_TO}"
        echo "Subject: ${subject}"
        echo "Date: $(date -R)"
        echo "Content-Type: text/plain; charset=UTF-8"
        echo
        echo "Arch updated ${trigger}: ${old} -> ${new}"
        [[ -n "$change" ]] && echo "Library change: ${change}"
        echo
        echo "Time to rebuild: ${rebuild}"
        echo
        echo "What to do: ${hint}"
        echo
        echo "Detected: $(alert_get "$file" detected)"
        echo "Click Seen on the desktop notification to stop the reminders."
    } >"$msg"
    # The password goes in through a curl config on a pipe, so it never shows up in ps.
    if curl --silent --show-error --ssl-reqd --max-time 60 \
        --url "smtps://${SMTP_HOST:-smtp.gmail.com}:465" \
        --mail-from "${MAIL_FROM:-$SMTP_USER}" --mail-rcpt "$MAIL_TO" \
        --upload-file "$msg" -K <(printf 'user = "%s:%s"\n' "$SMTP_USER" "$SMTP_PASS"); then
        sed -i 's/^mailed=no$/mailed=yes/' "$file"
        log_success "Mailed: ${subject}"
    else
        log_warn "Mail failed for ${trigger} -- retrying on the next run"
    fi
    rm -f "$msg"
}

mail_pending() {
    local file
    for file in "$PENDING"/*; do
        [[ -f "$file" ]] || continue
        [[ "$(alert_get "$file" mailed)" == "no" ]] || continue
        if [[ ! -r "$MAIL_CONF" ]]; then
            log_warn "No ${MAIL_CONF} -- desktop notification only"
            return 0
        fi
        send_mail "$file"
    done
}

# Each notification waits for its click in its own transient unit: the oneshot
# service would otherwise kill it on exit. The fixed unit name avoids duplicates
# while one is still on screen.
notify_pending() {
    local file id unit
    for file in "$PENDING"/*; do
        [[ -f "$file" ]] || continue
        id="$(basename "$file")"
        unit="kiro-rebuild-ack-${id}"
        if systemctl --user is-active --quiet "${unit}.service"; then
            echo "${id}: notification still on screen"
            continue
        fi
        systemd-run --user --collect --quiet --unit="$unit" "$SELF" --notify "$id" \
            || log_warn "Could not start the notification for ${id}"
    done
}

xml_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"
}

show_notification() {
    local id="$1" file="${PENDING}/$1" answer body
    [[ -f "$file" ]] || return 0
    body="Arch updated $(alert_get "$file" trigger) $(alert_get "$file" old) -> $(alert_get "$file" new)."
    [[ -n "$(alert_get "$file" change)" ]] && body+=$'\n'"$(alert_get "$file" change)"
    body+=$'\n'"$(alert_get "$file" hint)"
    answer="$(notify-send --app-name="Kiro rebuild watch" --icon=software-update-urgent \
        --urgency=critical --expire-time=0 --action=seen=Seen --wait \
        "Time to build: $(alert_get "$file" rebuild)" "$(xml_escape "$body")" || true)"
    if [[ "$answer" == "seen" ]]; then
        ack_alert "$id"
    else
        echo "${id}: closed without Seen -- shown again on the next run"
    fi
}

ack_alert() {
    local id="$1"
    if [[ ! -f "${PENDING}/${id}" ]]; then
        log_warn "No pending alert ${id}"
        return 0
    fi
    mkdir -p "$ACKED"
    mv "${PENDING}/${id}" "${ACKED}/${id}"
    log_success "${id} marked as seen"
}

show_status() {
    local file found=false
    log_section "Pending rebuild alerts"
    for file in "$PENDING"/*; do
        [[ -f "$file" ]] || continue
        found=true
        printf '%s%s%s  %s -> %s  build: %s  (detected %s, mailed %s)\n' "$CYAN" "$(basename "$file")" "$RESET" \
            "$(alert_get "$file" old)" "$(alert_get "$file" new)" "$(alert_get "$file" rebuild)" \
            "$(alert_get "$file" detected)" "$(alert_get "$file" mailed)"
    done
    $found || echo "None"
}

#####################################################################
# Main
#####################################################################
main() {
    mkdir -p "$STATE_DIR" "$PENDING"
    case "${1:-}" in
        --notify)
            show_notification "${2:?alert id}"
            return 0
            ;;
        --ack)
            ack_alert "${2:?alert id}"
            return 0
            ;;
        --status)
            show_status
            return 0
            ;;
        --test)
            create_alert "TEST" "1.0" "2.0" "nothing (test alert)" "This is a test of the rebuild watch: click Seen."
            ;;
        "")
            exec 9>"${STATE_DIR}/lock"
            if ! flock -n 9; then
                log_info "Another rebuild-watch run is busy"
                return 0
            fi
            sync_db
            check_triggers
            ;;
        *)
            log_error "Unknown option: $1"
            return 1
            ;;
    esac
    mail_pending
    notify_pending
    log_success "$(basename "$0") done"
}

main "$@"
