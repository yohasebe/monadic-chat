# Adding Docker Containers

## How to Add Containers

To add a Docker container, create a folder in `~/monadic/data/services` or `~/monadic/data/apps/<your_app>/services` and put these files in it:

- `compose.yml`
- `Dockerfile`
- Any other files the container needs

To build it, choose **Actions → Build User Containers**. This:

1. Finds every `compose.yml` in those `services` folders
2. Builds the containers with `--no-cache`
3. Writes the build log to `~/monadic/log/docker_build.log`

Start does not rebuild user containers. After you add or change a container definition, run **Build User Containers** again.

When user containers are present, Monadic Chat writes `~/monadic/config/compose.yml`, which includes the system containers and the user containers. The containers start together on Start and stop together.

## Minimal Example

### compose.yml
```yaml
services:
  my_service:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: monadic-chat-my-service-container
    networks:
      - monadic-chat-network
    volumes:
      - ~/monadic/data:/monadic/data
      - ~/monadic/data/apps:/monadic/data/apps:ro
      - ~/monadic/data/helpers:/monadic/data/helpers:ro
      - ~/monadic/data/services:/monadic/data/services:ro
    environment:
      - MY_ENV_VAR=value

networks:
  monadic-chat-network:
    driver: bridge
```

### Dockerfile
```dockerfile
FROM ubuntu:22.04

# Install your dependencies
RUN apt-get update && apt-get install -y \
    your-packages-here && \
    rm -rf /var/lib/apt/lists/*

# Copy your files
COPY your-script.sh /usr/local/bin/

# Set working directory
WORKDIR /monadic/data

# Keep container running
CMD ["tail", "-f", "/dev/null"]
```

## Important Requirements

1. **Network**: Connect the container to `monadic-chat-network`, defined with `driver: bridge` as in the example. The system containers define the network the same way.
2. **Shared folder**: Bind-mount `~/monadic/data` at `/monadic/data`. Mount `apps`, `helpers` and `services` read-only, as the system containers do, so that code run in the container cannot change the apps and helpers that Monadic Chat loads.
3. **Container name**: Name the container `monadic-chat-<name>-container`. An app runs commands in it with `send_command(command: "...", container: "<name>")`; see [Developing Apps](develop_apps.md#calling-functions-in-the-app).
4. **Keep alive**: Use a command such as `tail -f /dev/null` so that the container keeps running.

## Reference

The system containers in the repository are complete examples: for instance `docker/services/python/compose.yml` and `docker/services/python/Dockerfile` on [GitHub](https://github.com/yohasebe/monadic-chat). Some of their settings are needed only by system containers and not by user containers: compose `profiles`, `image`, `cache_from`, and the build arguments that **Install Options** sets.

## Troubleshooting

- **Build fails**: Check `~/monadic/log/docker_build.log`.
- **Container does not start**: Check the `compose.yml` syntax and the network definition.
- **Shared files are not visible**: Check the `~/monadic/data:/monadic/data` mount.
- **No user containers are found**: The build reports this when no `compose.yml` is in the `services` folders.
