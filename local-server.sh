#!/bin/bash
# local-server.sh — start/stop a simple HTTP server for testing DuckAILocalServer

set -euo pipefail

usage() {
    echo "Usage:"
    echo "  $0 start <port>   Start a simple HTTP server on the given port"
    echo "  $0 stop <port>    Kill whatever process is listening on the given port"
    echo "  $0 status <port>  Check if something is listening on the given port"
    exit 1
}

[[ $# -lt 2 ]] && usage

ACTION="$1"
PORT="$2"

case "$ACTION" in
    start)
        if lsof -ti :"$PORT" > /dev/null 2>&1; then
            echo "Port $PORT is already in use:"
            lsof -i :"$PORT"
            exit 1
        fi
        echo "Starting HTTP server on port $PORT (pid will be printed below)"
        python3 -m http.server "$PORT" --bind 127.0.0.1 &
        echo "PID: $!"
        echo "Stop with: $0 stop $PORT"
        ;;
    stop)
        PIDS=$(lsof -ti :"$PORT" 2>/dev/null || true)
        if [[ -z "$PIDS" ]]; then
            echo "Nothing listening on port $PORT"
            exit 0
        fi
        echo "Killing process(es) on port $PORT: $PIDS"
        echo "$PIDS" | xargs kill -9
        echo "Done"
        ;;
    status)
        if lsof -ti :"$PORT" > /dev/null 2>&1; then
            echo "Port $PORT is in use:"
            lsof -i :"$PORT"
        else
            echo "Nothing listening on port $PORT"
        fi
        ;;
    *)
        usage
        ;;
esac
