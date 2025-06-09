#!/bin/bash

# Simply start Ollama service
# Model downloads are now handled during container build process
exec /bin/ollama serve
