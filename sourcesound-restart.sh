#!/bin/bash
# SoundSource Trial Mode Workaround
#
# If media-control is installed (brew install media-control):
#   → reacts to track transitions via event stream, before the trial noise hits
#   → pauses the player during restart, resumes after → no audio spike
#
# Without media-control:
#   → falls back to popup detection (Accessibility API)
#   → restarts when trial dialog appears (brief audio spike on USB DACs)

set -euo pipefail

# Ensure Homebrew binaries are visible when running under launchd (minimal PATH)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

CONFIG_FILE="${HOME}/.config/sourcesound-restart/config"
LOG_FILE="${HOME}/.config/sourcesound-restart/sourcesound-restart.log"

mkdir -p "${HOME}/.config/sourcesound-restart"

# ── Defaults ──────────────────────────────────────────────────────────────────
TRIAL_INTERVAL=1200      # SoundSource trial noise fires every 20 min (1200s)
RESTART_MARGIN=90        # restart when this many seconds remain before trial noise
RESTART_DELAY=3          # seconds to wait after kill before relaunching
MUTE_EXTRA_WAIT=0        # extra seconds paused after relaunch (PEQ/plugin init time)
POPUP_POLL_INTERVAL=3    # seconds between popup checks
POPUP_COOLDOWN=300       # seconds to skip popup checks after a restart

[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# ── Helpers ───────────────────────────────────────────────────────────────────
is_soundsource_running() {
    pgrep -ix "SoundSource" > /dev/null 2>&1
}

# Returns epoch timestamp of when SoundSource was last started,
# by reading the process elapsed time. Falls back to now if SS is not running.
ss_start_epoch() {
    local pid etime
    pid=$(pgrep -ix SoundSource 2>/dev/null | head -1) || true
    [[ -z "$pid" ]] && { date +%s; return; }
    etime=$(ps -p "$pid" -o etime= 2>/dev/null | xargs) || true
    [[ -z "$etime" ]] && { date +%s; return; }
    python3 -c "
import time
s = '${etime}'.replace('-', ':').split(':')
p = [int(x) for x in s]
if   len(p) == 2: e = p[0]*60 + p[1]
elif len(p) == 3: e = p[0]*3600 + p[1]*60 + p[2]
else:             e = p[0]*86400 + p[1]*3600 + p[2]*60 + p[3]
print(int(time.time()) - e)
" 2>/dev/null || date +%s
}

ss_past_threshold() {
    is_soundsource_running || return 1
    local uptime threshold
    uptime=$(( $(date +%s) - $(ss_start_epoch) ))
    threshold=$(( TRIAL_INTERVAL - RESTART_MARGIN ))
    (( uptime > threshold ))
}

# Parse title and duration from a media-control JSON line (stdin).
# media-control wraps data in {"type":"data","payload":{...}}.
# Prints two lines: title, then duration (integer seconds).
mc_parse() {
    python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    p = d.get('payload', {})
    print(p.get('title') or '')
    print(int(p.get('duration') or 0))
except Exception:
    print('')
    print(0)
" 2>/dev/null || printf '\n0'
}

# ── Core restart ──────────────────────────────────────────────────────────────
# Caller is responsible for pausing the player before calling this,
# and resuming after. This function only handles SS kill/relaunch.
do_restart() {
    if pkill -ix "SoundSource" 2>/dev/null; then
        log "  SoundSource killed"
    else
        log "  SoundSource was not running — starting fresh"
    fi

    sleep "$RESTART_DELAY"

    if ! is_soundsource_running; then
        open -a "SoundSource" 2>/dev/null
        log "  SoundSource launched"
        sleep 1
    fi

    if (( MUTE_EXTRA_WAIT > 0 )); then
        sleep "$MUTE_EXTRA_WAIT"
    fi
}

# ── Smart restart mode (media-control) ────────────────────────────────────────
# Listens to the media-control event stream. At each new song:
#   1. Checks if elapsed_since_restart + new_song_duration would exceed the trial window
#   2. If yes → pauses the player, restarts SS, resumes (seamless, no spike)
#   3. If no  → does nothing
# Also checks for the trial popup every POPUP_POLL_INTERVAL seconds as a fallback
# (catches songs longer than 20 min). Uses read timeout instead of polling.
# If the stream closes (e.g. music stops), waits 5s and reopens — no exit needed.
smartrestart_mode() {
    log "media-control detected — starting smart restart mode"
    log "  threshold: ${TRIAL_INTERVAL}s trial - ${RESTART_MARGIN}s margin = $(( TRIAL_INTERVAL - RESTART_MARGIN ))s"

    # On startup: if SS is already past the safe threshold, restart immediately
    if is_soundsource_running; then
        local elapsed_at_start threshold_val
        elapsed_at_start=$(( $(date +%s) - $(ss_start_epoch) ))
        threshold_val=$(( TRIAL_INTERVAL - RESTART_MARGIN ))
        log "  SoundSource uptime at start: ${elapsed_at_start}s"
        if (( elapsed_at_start > threshold_val )); then
            log "  Already past threshold — immediate restart"
            media-control pause 2>/dev/null || true
            do_restart
            media-control play 2>/dev/null || true
        fi
    fi

    local last_track=""
    while true; do
        while true; do
            local line="" read_status=0
            # read exit codes: 0 = got data, 1 = EOF (stream died), >128 = timeout (normal)
            # Use || to prevent set -e from exiting on read timeout (non-zero but not fatal)
            IFS= read -r -t "$POPUP_POLL_INTERVAL" line <&3 || read_status=$?
            if (( read_status == 1 )); then
                log "media-control stream ended — retrying in 5s"
                break
            fi

            # ── Time-based fallback (for songs longer than 20 min) ────────────
            # Checks SS uptime directly — no Accessibility permission needed.
            if ss_past_threshold; then
                local uptime=$(( $(date +%s) - $(ss_start_epoch) ))
                log "Time-based fallback restart (SS uptime=${uptime}s, mid-song)"
                media-control pause 2>/dev/null || true
                do_restart
                media-control play 2>/dev/null || true
                # Fetch current song to prevent immediate proactive re-restart for the same song
                last_track=$(media-control get 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d.get('payload', d)
print(p.get('title') or '')
" 2>/dev/null || echo "")
                continue
            fi

            [[ -z "$line" ]] && continue

            # ── Track transition check ─────────────────────────────────────────
            local parsed current_track duration
            parsed=$(mc_parse <<< "$line")
            current_track=$(echo "$parsed" | sed -n '1p')
            duration=$(echo "$parsed" | sed -n '2p')

            [[ -z "$current_track" ]] && continue
            [[ "$current_track" == "$last_track" ]] && continue

            # New song detected
            last_track="$current_track"

            # If duration was absent from the event, fetch it
            if [[ "$duration" == "0" ]]; then
                duration=$(media-control get | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d.get('payload', d)
print(int(p.get('duration') or 0))
" 2>/dev/null || echo "0")
            fi

            local now elapsed threshold
            now=$(date +%s)
            elapsed=$(( now - $(ss_start_epoch) ))
            threshold=$(( TRIAL_INTERVAL - RESTART_MARGIN ))

            if (( elapsed + duration > threshold )); then
                # Only pause when a restart is actually needed
                media-control pause 2>/dev/null || true
                log "Proactive restart before: \"${current_track}\""
                log "  elapsed=${elapsed}s + song=${duration}s = $(( elapsed + duration ))s > ${threshold}s threshold"
                do_restart
                media-control play 2>/dev/null || true
            fi
        done 3< <(media-control stream)
        sleep 5
    done
}

# ── Popup-only mode ───────────────────────────────────────────────────────────
popup_mode() {
    log "media-control not found — falling back to time-based restart"
    log "  Install with: brew install media-control"
    log "  threshold: ${TRIAL_INTERVAL}s trial - ${RESTART_MARGIN}s margin = $(( TRIAL_INTERVAL - RESTART_MARGIN ))s"
    log "  poll: ${POPUP_POLL_INTERVAL}s"

    while true; do
        sleep "$POPUP_POLL_INTERVAL"

        if ss_past_threshold; then
            local uptime=$(( $(date +%s) - $(ss_start_epoch) ))
            log "Time-based restart (SS uptime=${uptime}s)"
            do_restart
        fi
    done
}

# ── Entry point ───────────────────────────────────────────────────────────────
log "=== sourcesound-restart started ==="

if command -v media-control &>/dev/null; then
    smartrestart_mode
else
    popup_mode
fi
