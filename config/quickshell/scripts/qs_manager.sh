#!/usr/bin/env bash
# Quickshell IPC manager — sends commands via Unix socket
# Usage: qs_manager.sh toggle <widget>
#        qs_manager.sh open <widget>
#        qs_manager.sh close

SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell.sock"

if [ $# -lt 1 ]; then
    echo "Usage: $0 {toggle|open|close} [widget]"
    exit 1
fi

# Check socket exists
if [ ! -S "$SOCKET" ]; then
    echo "Error: quickshell socket not found at $SOCKET"
    echo "Is quickshell running?"
    exit 1
fi

# Check something is listening (socat will fail fast if not)
action="$1"
widget="${2:-}"

case "$action" in
    toggle)
        [ -z "$widget" ] && { echo "Error: toggle requires a widget name"; exit 1; }
        if ! echo "toggle:$widget" | socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null; then
            echo "Error: failed to connect to socket (quickshell may have crashed)"
            exit 1
        fi
        ;;
    open)
        [ -z "$widget" ] && { echo "Error: open requires a widget name"; exit 1; }
        echo "open:$widget" | socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null
        ;;
    close)
        echo "close" | socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null
        ;;
    refresh)
        echo "refresh" | socat - UNIX-CONNECT:"$SOCKET" 2>/dev/null
        ;;
    *)
        echo "Unknown action: $action"
        echo "Usage: $0 {toggle|open|close|refresh} [widget]"
        exit 1
        ;;
esac
