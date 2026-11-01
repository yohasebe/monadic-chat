# Docker Build Caching

This page describes when the Ruby and Python images are built or downloaded, and which cache each build uses. The logic is in `docker/monadic.sh`.

## At Start

`start_docker_compose` decides what to build:

| Situation | What happens |
|---|---|
| Containers missing, or first install (`needs_full_rebuild`) | Full `docker compose build --no-cache` of every service with a build section, then `up -d`. A failed build stops Start |
| Version update with changed Python, Selenium or Embeddings Dockerfiles (`needs_selective_rebuild`) | Ruby is rebuilt with cache. Python is built with `docker compose build` (the prebuilt image is pulled first and used through `cache_from`); Selenium and Embeddings are pulled |
| Version update or Gem change only (`needs_ruby_rebuild`) | Only Ruby is rebuilt, with cache |
| Nothing changed | No build |

`check_dockerfiles_changed` compares hashes of the Python, Selenium and Embeddings Dockerfiles. The Ruby image carries the label `com.monadic.gems_hash` (SHA256 of `Gemfile` and `monadic.gemspec`); a different value triggers a Ruby rebuild. `FORCE_RUBY_REBUILD_NO_CACHE=true` makes Ruby builds use `--no-cache`.

User containers are never built at Start; **Actions → Build User Containers** builds them with `--no-cache`.

## Python Image (`build_python_container`)

| Condition | Build |
|---|---|
| `FORCE_REBUILD=true` (set by **Actions → Build Python Container**) | `docker build --no-cache` |
| No install options on and no `~/monadic/config/pysetup.sh` | The prebuilt `ghcr.io/yohasebe/monadic-python:${MONADIC_IMAGE_TAG:-latest}` is pulled instead of built (local build if the pull fails) |
| Otherwise | The prebuilt image is pulled and used with `--cache-from`, so only the layers of the enabled options are built |

Each option has its own conditional `RUN` layer keyed on its build `ARG`, so BuildKit reuses unchanged option layers. The options are the `PY_OPTIONS` list in `monadic.sh`: `INSTALL_LATEX`, `PYOPT_NLTK`, `PYOPT_SPACY`, `PYOPT_GENSIM`, `PYOPT_LIBROSA`, `PYOPT_MEDIAPIPE`, `PYOPT_TRANSFORMERS`, `IMGOPT_IMAGEMAGICK`.

The build is atomic:

1. Build (or pull) into a temporary tag `yohasebe/monadic-chat:python-build-<timestamp>`.
2. Run health checks (`python_health.json`) and write `python_meta.json`.
3. Retag the image as the current Python image; a failed build keeps the current image.
4. If the Python container is running, `recreate_python_container` runs `compose up -d --force-recreate --no-deps --pull never --no-build python_service` and checks that the container uses the new image ID. Otherwise the new image is used at the next Start.

Logs (overwritten on each build): `~/monadic/log/docker_build_python.log`, `python_health.json`, `python_meta.json`. `~/monadic/log/python_build_options.txt` records the options of the last build; changes are logged as `[INFO] Install options changed: …` and do not change the cache strategy.

### Install Options and Start

Saving Install Options does not build. At the next Start, the app compares the saved options with the built image and offers **Rebuild and Start** (`build_python_container_update`), which uses the rules above.

## Setup Scripts as Build Secrets

`~/monadic/config/pysetup.sh` and `rbsetup.sh` run at the end of the Python and Ruby image builds. They are passed as BuildKit secrets and are not copied into the build context or left in the image:

- `docker build` gets `--secret id=pysetup,src=<file>` (or `rbsetup`) and `--build-arg PYSETUP_SHA=<sha256>` from `set_setup_script_build_flags`.
- `docker compose build` reads the secret from the environment: `secrets: pysetup: environment: MONADIC_PYSETUP_CONTENT` in the service's `compose.yml`. `monadic.sh` sets `MONADIC_PYSETUP_CONTENT` / `MONADIC_RBSETUP_CONTENT` just before each compose build and unsets them right after (`export_setup_script_contents` / `unset_setup_script_contents`).
- The Dockerfile step is `RUN --mount=type=secret,id=pysetup,required=false …`, which runs the script only when the secret has content. The `*_SHA` argument reruns the step when the script changes. Builds without the secret (CI) skip it.

## Manual Checks

```bash
# Option ARG values of the current image
docker inspect yohasebe/python:latest --format '{{json .Config.Labels}}'

# Build locally the way monadic.sh does (with options and an optional setup script)
DOCKER_BUILDKIT=1 docker build \
  --cache-from ghcr.io/yohasebe/monadic-python:latest \
  --build-arg INSTALL_LATEX=true \
  --secret id=pysetup,src=$HOME/monadic/config/pysetup.sh \
  --build-arg PYSETUP_SHA=$(shasum -a 256 ~/monadic/config/pysetup.sh | cut -d' ' -f1) \
  -t test-python docker/services/python
```

## Pitfall

In `monadic.sh`, `${cache_flags}` must stay unquoted so that an empty value expands to nothing; a quoted empty string becomes an empty argument to `docker build`.
