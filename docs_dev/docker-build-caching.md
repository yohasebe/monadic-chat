# Docker Build Caching Strategy

## Overview

Monadic Chat uses intelligent build caching for the Python container to balance build speed with reliability when install options change.

## How It Works

### Complete Build Flow

```
User changes install option in Electron UI
          ↓
Electron saves to ~/monadic/config/env
          ↓
User triggers "Build Python Container"
          ↓
Electron spawns monadic.sh with env vars from config file
          ↓
read_cfg_bool() reads env vars (priority 1) or config file (priority 2)
          ↓
Compare with ~/monadic/log/python_build_options.txt
          ↓
    ┌─────────────────────┬──────────────────────┐
    │                     │                      │
Options changed      Options unchanged    First build
    │                     │                      │
    ↓                     ↓                      ↓
--no-cache          Use cache            --no-cache
(15-30 min)         (1-2 min)            (15-30 min)
    │                     │                      │
    └─────────────────────┴──────────────────────┘
                          ↓
              Docker build creates new image
                          ↓
              Tag as yohasebe/python:latest
                          ↓
              Health check passes?
                          ↓
                    ┌─────┴─────┐
                    │           │
                  Yes          No
                    │           │
                    ↓           ↓
          Save options    Keep old image
          to .txt file    Clean temp image
                    │           │
                    ↓           └─→ FAIL
          Is container running?
                    │
              ┌─────┴─────┐
              │           │
            Yes          No
              │           │
              ↓           ↓
    Restart container   Skip restart
    (use new image)    (new image used
                        on next start)
              │           │
              └─────┬─────┘
                    ↓
              SUCCESS - New image in use
```

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

### Container Auto-Restart

After a successful build, the system automatically restarts the Python container if it's running:

```bash
# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "^monadic-chat-python-container$"; then
  # Restart using docker compose
  docker compose restart python_service
fi
```

**Why this is necessary:**
- Building a new Docker image does NOT automatically update running containers
- Containers continue using the old image until restarted
- Without auto-restart, users would need to manually stop/start containers
- This could lead to confusion: "I rebuilt but packages are still missing!"

**Implementation location:** `docker/monadic.sh:588-599`

### Verifying Successful Build and Restart

After a build completes, verify the container is using the new image:

```bash
# 1. Check container creation time (should be recent)
docker ps --filter "name=monadic-chat-python-container" --format "{{.CreatedAt}}"

# 2. Verify container is using latest image
docker inspect monadic-chat-python-container --format='{{.Image}}' > /tmp/container_img
docker images yohasebe/python:latest --format "{{.ID}}" > /tmp/latest_img
diff /tmp/container_img /tmp/latest_img  # Should be identical

# 3. For LaTeX builds, verify package count
docker exec monadic-chat-python-container bash -c "dpkg -l | grep -i latex | wc -l"
# Should return 100+ if INSTALL_LATEX=true, 0 if false

# 4. Verify critical tools are present
docker exec monadic-chat-python-container bash -c "which dvisvgm && kpsewhich CJKutf8.sty"
```

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

### Container using old image after rebuild

**Symptom:** After rebuilding with `INSTALL_LATEX=true`, LaTeX packages still show 0 count.

**Diagnosis:**
```bash
# Check when container was created
docker ps -a --format "{{.Names}}\t{{.CreatedAt}}" | grep python

# Check when latest image was built
docker images yohasebe/python:latest --format "{{.CreatedAt}}"

# If container creation time is BEFORE image build time, container is using old image
```

**Cause:** Docker build creates a new image but doesn't update running containers.

**Solution (automatic):** The build system now automatically restarts the container after successful build (implemented in commit `86d2bca6`).

**Manual workaround (if needed):**
```bash
docker compose restart python_service
# or
docker stop monadic-chat-python-container
docker rm monadic-chat-python-container
docker compose up -d python_service
```

## Development Notes

### Key Learnings from Implementation

**1. Environment Variable Propagation**
- Electron app reads `~/monadic/config/env` and passes variables via `spawn(..., { env: {...process.env, ...envConfig} })`
- Original `read_cfg_bool` only checked config file, not environment variables
- **Fix:** Modified to check environment variables FIRST using `eval echo "\${key}"`
- **Location:** `docker/monadic.sh:392-420`

**2. Docker Build Cache Behavior**
- Docker caches layers even when `ARG` values change
- Example: `ARG INSTALL_LATEX=true` vs `false` might still use same cached `RUN if [ "$INSTALL_LATEX" = "true" ]` layer
- **Evidence:** `docker history` showed `INSTALL_LATEX=false` in final image despite passing `--build-arg INSTALL_LATEX=true`
- **Root cause:** Conditional RUN commands are evaluated during execution, but cache key is based on Dockerfile text only
- **Solution:** Use `--no-cache` when ARG values actually change

**3. Container vs Image Lifecycle**
- **Image:** Built once, immutable, tagged (e.g., `yohasebe/python:latest`)
- **Container:** Runtime instance of an image, continues using original image until recreated/restarted
- **Critical insight:** `docker build` updating `latest` tag does NOT affect running containers
- **Solution:** Auto-restart container after build to force use of new image

**4. Bash Indirect Variable Reference**
- Initial attempt: `${!key}` → Failed with "bad substitution" error
- **Working solution:** `eval echo "\${key}"` (more portable)
- **Use case:** Checking if environment variable exists by name stored in `$key`

**5. Change Detection Strategy**
- Compare 9 install options between current and previous build
- Save state to `~/monadic/log/python_build_options.txt` after success
- Use `--no-cache` only when options differ (15-30 min) vs cache when unchanged (1-2 min)
- **Trade-off:** Reliability (correct packages) vs Speed (fast rebuilds)
- **Result:** Best of both worlds

### Testing Methodology

**To verify the fix works correctly:**

1. **Test 1: Enable LaTeX**
   ```bash
   # Set INSTALL_LATEX=true in config
   echo "INSTALL_LATEX=true" >> ~/monadic/config/env
   # Build via Electron menu
   # Verify: dpkg -l | grep -i latex | wc -l → should be 100+
   ```

2. **Test 2: Disable LaTeX**
   ```bash
   # Set INSTALL_LATEX=false
   echo "INSTALL_LATEX=false" >> ~/monadic/config/env
   # Rebuild
   # Verify: dpkg -l | grep -i latex | wc -l → should be 0
   ```

3. **Test 3: No change rebuild**
   ```bash
   # Rebuild without changing options
   # Should see: "[INFO] Install options unchanged, using build cache"
   # Build time should be ~1-2 minutes
   ```

4. **Test 4: Container auto-restart**
   ```bash
   # After any build, check container creation time
   # Should be within seconds of build completion
   docker ps --format "{{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | grep python
   ```

### Common Pitfalls to Avoid

1. **Don't quote `${cache_flag}` in docker build command**
   - ❌ Wrong: `docker build "${cache_flag}" ...`
   - ✅ Correct: `docker build ${cache_flag} ...`
   - Reason: When empty, quoted becomes `""` which is treated as an argument, unquoted becomes nothing

2. **Don't use `${!key}` for indirect variable reference**
   - May fail on some Bash versions with "bad substitution"
   - Use `eval echo "\${key}"` instead

3. **Don't assume `docker build` updates running containers**
   - Always restart or recreate containers after building new images
   - This is now handled automatically

4. **Don't skip option change detection**
   - Always saves performance when options unchanged
   - Ensures reliability when options change

## Related Files

- `docker/monadic.sh`: Build logic and change detection (lines 422-586)
- `app/main.js`: Electron menu and environment variable passing (lines 2446-2469)
- `~/monadic/config/env`: User configuration file
- `~/monadic/log/python_build_options.txt`: Saved options from last build
- `docker/services/python/Dockerfile`: Python container definition

## Implementation History

This feature was developed in response to a user-reported issue where the Syntax Tree app failed to generate images due to missing LaTeX/CJK packages.

**Commits:**
- `fc56c74a`: Clarify bracket notation format in Syntax Tree prompts
- `423ad8de`: Implement smart caching for Python container builds
- `618c5480`: Remove debug output from build caching implementation
- `86d2bca6`: Auto-restart Python container after build to use new image

**Original Issue:**
- User set `INSTALL_LATEX=true` in Electron menu and ran "Build All"
- LaTeX packages were not installed despite being in Dockerfile
- Root cause: Environment variable propagation + Docker cache behavior

**Development Process:**
1. **Investigation**: Discovered `read_cfg_bool` didn't check environment variables
2. **First Fix**: Modified `read_cfg_bool` to check env vars first
3. **Cache Problem**: Docker cache bypassed even with correct env vars
4. **Smart Caching**: Implemented change detection to use `--no-cache` only when needed
5. **Container Issue**: Discovered running containers don't auto-update to new images
6. **Final Fix**: Added automatic container restart after successful build
7. **Documentation**: Created comprehensive guide with testing methodology

**Testing Confirmed:**
- ✅ LaTeX on/off toggle works correctly
- ✅ Container automatically uses latest image after rebuild
- ✅ Fast rebuilds (~1-2 min) when options unchanged
- ✅ Complete rebuilds (~15-30 min) when options change
- ✅ Syntax Tree app generates Japanese syntax trees successfully

## See Also

- [Docker Architecture](docker-architecture.md)
- [Development Workflow](../docs/developer/development_workflow.md)
- [Syntax Tree App Documentation](../docs/apps/syntax_tree.md)
