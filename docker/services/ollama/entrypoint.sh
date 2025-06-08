#!/bin/bash

# Start Ollama in the background.
/bin/ollama serve &
# Record Process ID.
pid=$!

# Pause for Ollama to start.
sleep 5

# Check if olsetup.sh exists in the config directory
if [ -f "/monadic/config/olsetup.sh" ]; then
    echo "Running custom setup script..."
    chmod +x /monadic/config/olsetup.sh
    /monadic/config/olsetup.sh
    echo "Custom setup completed."
else
    echo "No custom setup script found at /monadic/config/olsetup.sh"
    echo "Pulling default model: llama3.2..."
    ollama pull llama3.2
    echo "Default model pulled."
fi

# Wait for Ollama process to finish.
wait $pid
