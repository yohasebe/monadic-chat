#!/bin/bash

# Script to start or stop JupyterLab
# Usage:
# ./script_name.sh run   # To start JupyterLab
# ./script_name.sh stop  # To stop JupyterLab

# Determine the directory where the script is located
SCRIPT_DIR=$(dirname "$0")

start_jupyterlab() {
    jupyter labextension disable "@jupyterlab/apputils-extension:announcements"
    jupyter lab --core-mode --ip='*' --port=8889 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.terminado_settings='{"shell_command": ["/bin/bash"]}' > "$SCRIPT_DIR/jupyter_lab.log" 2>&1 &
    echo $! > "$SCRIPT_DIR/jupyter_lab.pid"
    echo "JupyterLab is running. PID: $(cat "$SCRIPT_DIR/jupyter_lab.pid")"
}

stop_jupyterlab() {
    if [ -f "$SCRIPT_DIR/jupyter_lab.pid" ]; then
        kill $(cat "$SCRIPT_DIR/jupyter_lab.pid") && rm "$SCRIPT_DIR/jupyter_lab.pid"
        echo "JupyterLab has been stopped."
    else
        echo "JupyterLab does not appear to be running."
    fi
}

if [ "$1" == "run" ]; then
    if [ -f "$SCRIPT_DIR/jupyter_lab.pid" ]; then
        echo "JupyterLab is already running. Restarting . . ."
        stop_jupyterlab
    fi
    start_jupyterlab
elif [ "$1" == "stop" ]; then
    stop_jupyterlab
else
    echo "Invalid argument. Use 'run' or 'stop'"
fi
