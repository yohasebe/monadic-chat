#!/bin/bash

# Script to start or stop JupyterLab
# Usage:
# ./script_name.sh run   # To start JupyterLab
# ./script_name.sh stop  # To stop JupyterLab

# Determine the directory where the script is located
SCRIPT_DIR=$(dirname "$0")

if [ "$1" == "run" ]; then
    jupyter labextension disable "@jupyterlab/apputils-extension:announcements"
    # Starts JupyterLab in the background and logs the PID in the script's directory
    jupyter lab --core-mode --ip='*' --port=8888 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.terminado_settings='{"shell_command": ["/bin/bash"]}' > "$SCRIPT_DIR/jupyter_lab.log" 2>&1 &
    echo $! > "$SCRIPT_DIR/jupyter_lab.pid"
    echo "JupyterLab is running. PID: $(cat "$SCRIPT_DIR/jupyter_lab.pid")"
elif [ "$1" == "stop" ]; then
    # Stops JupyterLab using the stored PID in the script's directory
    if [ -f "$SCRIPT_DIR/jupyter_lab.pid" ]; then
        kill $(cat "$SCRIPT_DIR/jupyter_lab.pid") && rm "$SCRIPT_DIR/jupyter_lab.pid"
        echo "JupyterLab has been stopped."
    else
        echo "JupyterLab does not appear to be running."
    fi
else
    echo "Invalid argument. Use 'run' or 'stop'"
fi
