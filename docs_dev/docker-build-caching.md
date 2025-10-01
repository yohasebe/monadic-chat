# Docker Build Caching Strategy

## Overview

Monadic Chat uses intelligent build caching for the Python container to balance build speed with reliability when install options change.

## How It Works

### Install Options Tracking

The build system tracks the following install options:
- `INSTALL_LATEX`: LaTeX toolchain for Syntax Tree and Concept Visualizer
- `PYOPT_NLTK`: Natural Language Toolkit
- `PYOPT_SPACY`: spaCy NLP library
- `PYOPT_SCIKIT`: scikit-learn machine learning library
- `PYOPT_GENSIM`: Topic modeling library
- `PYOPT_LIBROSA`: Audio analysis library
- `PYOPT_MEDIAPIPE`: Computer vision framework
- `PYOPT_TRANSFORMERS`: Hugging Face Transformers
- `IMGOPT_IMAGEMAGICK`: ImageMagick image processing

### Build Strategy

**When options haven't changed:**
- Uses Docker build cache for fast rebuilds (~1-2 minutes)
- Only rebuilds layers that actually changed
- Logs: `[INFO] Install options unchanged, using build cache for faster build`

**When options have changed:**
- Uses `--no-cache` to force complete rebuild (~15-30 minutes)
- Ensures new packages are properly installed
- Logs which options changed: `[INFO] Install options changed: INSTALL_LATEX(false→true)`
- Logs: `[INFO] Using --no-cache to ensure changes are applied`

**First build or missing options file:**
- Uses `--no-cache` to be safe
- Logs: `[INFO] First build or options file missing, using --no-cache`

### Options File Location

Previous build options are stored at:
```
~/monadic/log/python_build_options.txt
```

This file is automatically created/updated after each successful build.

## User Experience

### Changing Install Options

1. Open Electron app menu: **Actions → Install Options**
2. Toggle options (e.g., enable LaTeX for Syntax Tree app)
3. Click **Save**
4. Menu: **Actions → Build Python Container**
5. System detects the change and uses `--no-cache` automatically

Expected log output:
```
[INFO] Install options changed: INSTALL_LATEX(false→true)
[INFO] Using --no-cache to ensure changes are applied
[HTML]: <p>Starting Python image build (atomic) . . .</p>
...
[INFO] Saved build options to ~/monadic/log/python_build_options.txt
[HTML]: <p>Restarting Python container to use new image...</p>
[INFO] Python container restarted successfully
```

The system automatically restarts the Python container after a successful build to ensure the new image is immediately used.

### Rebuilding Without Changes

If you rebuild without changing options, the system uses cache:
```
[INFO] Install options unchanged, using build cache for faster build
```

This completes much faster as most layers are cached.

## Technical Details

### Environment Variable Priority

The `read_cfg_bool` function in `monadic.sh` checks options in this order:
1. **Environment variables** (passed by Electron during build)
2. **Config file** (`~/monadic/config/env`)
3. **Default value** (usually `false`)

### Change Detection Algorithm

```bash
# For each option:
1. Read previous value from python_build_options.txt
2. Compare with current value
3. If any option differs → use_no_cache=true
4. Build with appropriate cache strategy
5. On success → save current options to file
6. If Python container is running → restart it to use new image
```

### Why This Matters

**Problem it solves:**
- Docker's build cache can reuse layers even when `ARG` values change
- Without `--no-cache`, changing `INSTALL_LATEX` from `false` to `true` might still use cached layers built with `false`
- This results in missing packages despite correct build args

**Solution:**
- Detect actual option changes at the application level
- Force `--no-cache` only when truly needed
- Balance between reliability and build speed

## Troubleshooting

### Options not taking effect

If you change options but packages aren't installed:

1. **Check the build log** (`~/monadic/log/docker_build_python.log`):
   ```bash
   grep "Install options" ~/monadic/log/docker_build_python.log
   ```

2. **Verify saved options**:
   ```bash
   cat ~/monadic/log/python_build_options.txt
   ```

3. **Force complete rebuild** (if needed):
   ```bash
   # Remove the options file to trigger --no-cache
   rm ~/monadic/log/python_build_options.txt
   # Then rebuild via Electron menu
   ```

### Manual Docker builds

If building manually with `docker build`:
```bash
# Always use --no-cache when changing ARG values
docker build --no-cache \
  --build-arg INSTALL_LATEX=true \
  -t yohasebe/python \
  docker/services/python
```

## Related Files

- `docker/monadic.sh`: Build logic and change detection (lines 422-586)
- `app/main.js`: Electron menu and environment variable passing (lines 2446-2469)
- `~/monadic/config/env`: User configuration file
- `~/monadic/log/python_build_options.txt`: Saved options from last build
- `docker/services/python/Dockerfile`: Python container definition

## See Also

- [Docker Architecture](docker-architecture.md)
- [Development Workflow](../docs/developer/development_workflow.md)
