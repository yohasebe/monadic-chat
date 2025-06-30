#!/bin/bash

# Run tests for jupyter_controller.py

echo "Running Jupyter Controller Tests..."
echo "=================================="

# Change to the script directory
cd "$(dirname "$0")"

# Run the Python unit tests
python3 -m pytest test_jupyter_controller.py -v

# Alternative: Run with unittest directly
# python3 test_jupyter_controller.py

echo ""
echo "Test run completed."