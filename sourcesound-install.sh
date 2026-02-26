#!/bin/bash
# Install / uninstall the SourceSound restart service
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sourcesound-restart.sh"
PLIST="$HOME/Library/LaunchAgents/com.user.sourcesound-restart.plist"
LABEL="com.user.sourcesound-restart"
CONFIG_DIR="$HOME/.config/sourcesound-restart"

green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
red()    { echo -e "\033[31m$*\033[0m"; }

install() {
    green "=== Installing SourceSound restart service ==="

    mkdir -p "$CONFIG_DIR"
    green "✓ Config directory: $CONFIG_DIR"

    chmod +x "$SCRIPT"
    green "✓ Script is executable"

    mkdir -p "$HOME/Library/LaunchAgents"

    # Generate plist with the actual script location
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>

    <!-- Keep the daemon alive if it crashes or exits -->
    <key>KeepAlive</key>
    <true/>

    <!-- Start on login -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Restart delay after crash (seconds) -->
    <key>ThrottleInterval</key>
    <integer>10</integer>

    <!-- Log stdout/stderr -->
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/launchd.log</string>

    <!-- Only run when on AC or battery — no restrictions -->
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF
    green "✓ LaunchAgent plist generated: $PLIST"

    # Load the LaunchAgent
    if launchctl list "$LABEL" &>/dev/null 2>&1; then
        yellow "Service already loaded — reloading..."
        launchctl unload "$PLIST" 2>/dev/null || true
    fi

    launchctl load -w "$PLIST"
    green "✓ LaunchAgent loaded (will auto-start on login)"

    green ""
    green "Service is running. Config: $CONFIG_DIR/config"
    green "Logs:   $CONFIG_DIR/sourcesound-restart.log"
}

uninstall() {
    yellow "=== Uninstalling SourceSound restart service ==="
    launchctl unload "$PLIST" 2>/dev/null && green "✓ Service stopped and unloaded" || true
    yellow "Files kept in place. Remove manually if desired:"
    yellow "  $SCRIPT"
    yellow "  $PLIST"
    yellow "  $CONFIG_DIR/"
}

status() {
    echo "── Service status ──────────────────────────────"
    if launchctl list "$LABEL" &>/dev/null 2>&1; then
        green "RUNNING"
        launchctl list "$LABEL"
    else
        red "NOT RUNNING"
    fi
    echo ""
    echo "── Last 20 log lines ───────────────────────────"
    tail -20 "$CONFIG_DIR/sourcesound-restart.log" 2>/dev/null || echo "(no log yet)"
}

case "${1:-install}" in
    install)   install ;;
    uninstall) uninstall ;;
    status)    status ;;
    reload)
        launchctl kickstart -k "gui/$(id -u)/$LABEL"
        green "Service reloaded"
        ;;
    *)
        echo "Usage: $0 [install|uninstall|status|reload]"
        exit 1
        ;;
esac
