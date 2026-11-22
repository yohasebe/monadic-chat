#!/bin/bash
# Starts, stops and reports JupyterLab, one call at a time, so the chat's
# tools, the app's menu and the page's "open" share one server.
#
#   run_jupyter.sh run      starts JupyterLab unless it answers, and waits
#                           until it answers (READY_LIMIT seconds)
#   run_jupyter.sh stop     ends the JupyterLab this script started
#   run_jupyter.sh status   says whether JupyterLab answers
#
# JupyterLab answers when its /api/status gives its status. The server this
# script started is known by its process id and that process's start time,
# so a process that took the id after it ended is never signalled.

SCRIPT_DIR=$(dirname "$0")
PORT=8889
PID_FILE="$SCRIPT_DIR/jupyter_lab.pid"
LOG_FILE="$SCRIPT_DIR/jupyter_lab.log"
LOCK_FILE="$SCRIPT_DIR/jupyter_lab.lock"
READY_LIMIT=30
LOCK_LIMIT=60

# Whether JupyterLab answers on its port.
answers() {
    python3 - "$PORT" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
with urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/api/status", timeout=2) as response:
    sys.exit(0 if "started" in json.load(response) else 1)
PY
}

# The start time of a process (field 22 of /proc/<pid>/stat), or nothing.
start_time_of() {
    [ -r "/proc/$1/stat" ] && awk '{print $22}' "/proc/$1/stat"
}

# The process this script started, when it still runs: its id, else nothing.
our_server() {
    [ -f "$PID_FILE" ] || return 1
    read -r pid started < "$PID_FILE"
    [ -n "$pid" ] && [ -n "$started" ] && [ "$(start_time_of "$pid")" = "$started" ] && echo "$pid"
}

start_server() {
    jupyter labextension disable "@jupyterlab/apputils-extension:announcements" >/dev/null 2>&1
    jupyter lab --notebook-dir=/monadic/data --LabApp.default_url='/lab/tree' --ip='*' --port=$PORT \
        --ServerApp.port_retries=0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' \
        --NotebookApp.terminado_settings='{"shell_command": ["/bin/bash"]}' --ServerApp.allow_remote_access=False \
        > "$LOG_FILE" 2>&1 9>&- &
    local pid=$!
    echo "$pid $(start_time_of "$pid")" > "$PID_FILE"
}

# Waits until JupyterLab answers; fails at once when its process ended.
wait_ready() {
    local pid=$1
    local deadline=$((SECONDS + READY_LIMIT))
    while [ $SECONDS -lt $deadline ]; do
        answers && return 0
        [ -n "$pid" ] && [ ! -d "/proc/$pid" ] && return 2
        sleep 0.5
    done
    return 1
}

run() {
    if answers; then
        echo "JupyterLab is running."
        return 0
    fi
    local pid
    pid=$(our_server)
    if [ -z "$pid" ]; then
        rm -f "$PID_FILE"
        start_server
        pid=$(our_server)
    fi
    wait_ready "$pid"
    case $? in
        0) echo "JupyterLab is running." ;;
        2) rm -f "$PID_FILE"; echo "Error: JupyterLab did not start (port $PORT may be in use)."; return 1 ;;
        *) echo "Error: JupyterLab did not answer in time."; return 1 ;;
    esac
}

stop() {
    local pid
    pid=$(our_server)
    if [ -z "$pid" ]; then
        rm -f "$PID_FILE"
        echo "JupyterLab is not running."
        return 0
    fi
    kill "$pid"
    local deadline=$((SECONDS + 10))
    while [ -d "/proc/$pid" ] && [ $SECONDS -lt $deadline ]; do sleep 0.2; done
    rm -f "$PID_FILE"
    echo "JupyterLab has been stopped."
}

case "$1" in
    run|stop|status) ;;
    *) echo "Usage: $0 {run|stop|status}"; exit 1 ;;
esac

exec 9>"$LOCK_FILE"
if ! flock -w "$LOCK_LIMIT" 9; then
    echo "Error: JupyterLab is being started or stopped elsewhere."
    exit 1
fi

case "$1" in
    run) run ;;
    stop) stop ;;
    status) if answers; then echo "JupyterLab is running."; else echo "JupyterLab is not running."; exit 1; fi ;;
esac
