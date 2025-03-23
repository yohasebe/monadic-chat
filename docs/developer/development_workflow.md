# Development Workflow

This document contains guidelines and instructions for developers contributing to the Monadic Chat project.

## Managing Setup Scripts

The `pysetup.sh` and `rbsetup.sh` files located in `docker/services/python/` and `docker/services/ruby/` respectively can be customized by users to install additional packages during container build. When building locally, these files might be replaced with user-provided versions from the `~/monadic/config/` directory.

### Important: Reset Setup Scripts Before Committing

For version control consistency, we always want to commit the original versions of these scripts. Before committing changes to the repository, please reset these files using one of the methods below:

#### Method 1: Using the Reset Script

Run the provided reset script:

```bash
./docker/services/reset_setup_scripts.sh
```

This will restore the original versions of the setup scripts from git.

#### Method 2: Manual Reset

Alternatively, you can manually reset the files using git:

```bash
git checkout -- docker/services/python/pysetup.sh docker/services/ruby/rbsetup.sh
```

### Git Pre-commit Hook (Optional)

You can set up a git pre-commit hook to automatically reset these files before each commit:

1. Create a file named `pre-commit` in your `.git/hooks/` directory:

```bash
touch .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

2. Add the following content to the pre-commit hook:

```bash
#!/bin/bash
# .git/hooks/pre-commit - Automatically reset setup scripts before commit

# Get the files that are staged for commit
STAGED_FILES=$(git diff --cached --name-only)

# Check if our setup scripts are modified
if echo "$STAGED_FILES" | grep -q "docker/services/python/pysetup.sh\|docker/services/ruby/rbsetup.sh"; then
  echo "⚠️ Setup script changes detected in commit."
  echo "⚠️ Resetting to original versions from git..."
  
  # Reset them
  git checkout -- docker/services/python/pysetup.sh
  git checkout -- docker/services/ruby/rbsetup.sh
  
  # Re-add them to staging
  git add docker/services/python/pysetup.sh
  git add docker/services/ruby/rbsetup.sh
  
  echo "✅ Setup scripts reset. Proceeding with commit."
fi

# Allow the commit to proceed
exit 0
```

This pre-commit hook will automatically detect and reset any changes to the setup scripts before committing.

## For Users

Users who want to customize their containers should place custom scripts in:
- `~/monadic/config/pysetup.sh` for Python customizations
- `~/monadic/config/rbsetup.sh` for Ruby customizations

These will be automatically used when building containers locally, but won't affect the repository files.

## Avoiding Duplicate Container Builds

The Monadic Chat build system is optimized to avoid building containers multiple times unnecessarily. Recent improvements include:

1. Removing redundant `build_docker_compose` calls in container-specific build functions
2. Improving the logic in `start_docker_compose` to only rebuild when necessary
3. Using a boolean flag to track when rebuilds are needed

These changes make the build process more efficient by preventing duplicate builds and reducing unnecessary checks.