#!/bin/bash
# reset_setup_scripts.sh - Reset setup scripts to their original versions before committing

# Get the repository root directory
REPO_ROOT=$(git rev-parse --show-toplevel)

# Reset the setup scripts from git
git checkout -- "${REPO_ROOT}/docker/services/python/pysetup.sh"
git checkout -- "${REPO_ROOT}/docker/services/ruby/rbsetup.sh"
git checkout -- "${REPO_ROOT}/docker/services/ollama/olsetup.sh"

echo "✅ Setup scripts (pysetup.sh, rbsetup.sh, and olsetup.sh) have been reset to their original versions from git."
echo "You can now safely commit your changes."