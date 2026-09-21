# Uninstallation

## Basic Steps :id=basic-steps

The basic steps to uninstall Monadic Chat are as follows:

- Exit Monadic Chat
- Delete Docker containers and images
- Uninstall Monadic Chat

<!-- tabs:start -->

### **macOS**

1. Run `Remove Images/Containers/Data` from the menu. This will delete the Docker containers, images, and stored data (including PDF vector embeddings) shown below.
2. Exit Monadic Chat.
3. Open the `Applications` folder in Finder and drag Monadic Chat to the trash.

### **Windows**

1. Run `Remove Images/Containers/Data` from the menu. This will delete the Docker containers, images, and stored data (including PDF vector embeddings) shown below.
2. Exit Monadic Chat.
3. Uninstall Monadic Chat from `Add or Remove Programs`.

### **Linux**

1. Run `Remove Images/Containers/Data` from the menu. This will delete the Docker containers, images, and stored data (including PDF vector embeddings) shown below.
2. Exit Monadic Chat.
3. Delete the AppImage file you downloaded.

Monadic Chat ships as an AppImage, which is never installed into the system, so there is no package to remove:

```shell
$ rm monadic-chat_*.AppImage
```

If your desktop environment offered to integrate the AppImage into your application menu, remove the entry it created (usually under `~/.local/share/applications/`).

<!-- tabs:end -->

<!-- SCREENSHOT: Monadic Chat menu showing Actions menu with Remove Images/Containers/Data option -->

## User Data :id=user-data

After uninstallation, your personal data and settings remain in two places:

- `~/monadic/` (macOS/Linux) or `%USERPROFILE%\monadic\` (Windows) — configuration files, chat logs, and generated data
- The application's own storage (cookies, cached pages, window state):
  - macOS: `~/Library/Application Support/Monadic Chat`
  - Linux: `~/.config/Monadic Chat`
  - Windows: `%APPDATA%\Monadic Chat`

Delete both directories to remove every trace of Monadic Chat.

## Cleanup (Optional) :id=cleanup

If the containers, images, and data are not deleted even after running `Remove Images/Containers/Data`, or if problems occur during an update or uninstallation, you have two options:

### Option 1: Clean/Purge All Docker Data :id=clean-purge-docker-data

You can use Docker Desktop's menu: `Troubleshoot` → `Clean/Purge data` to remove all Docker images and containers. **Warning**: This will remove ALL Docker data on your system, including data from other applications, not just Monadic Chat's.

### Option 2: Manual Removal :id=manual-removal

Alternatively, you can manually delete only the Monadic Chat-related Docker containers and images:

### Docker Containers and Images :id=docker-containers-images

#### Containers

- `monadic-chat-ruby-container`
- `monadic-chat-python-container`
- `monadic-chat-selenium-container`
- `monadic-chat-qdrant-container`
- `monadic-chat-embeddings-container`
- `monadic-chat-privacy-container` (present unless you set `PRIVACY_FILTER=false`)
- `monadic-chat-extractor-container` (only present if the Knowledge Base Quality Pack is installed)

#### Images

- `yohasebe/monadic-chat`
- `yohasebe/python`
- `ghcr.io/yohasebe/monadic-embeddings`
- `ghcr.io/yohasebe/monadic-qdrant`
- `ghcr.io/yohasebe/monadic-selenium`
- `ghcr.io/yohasebe/monadic-privacy` (unless `PRIVACY_FILTER=false`)
- `ghcr.io/yohasebe/monadic-extractor` (only if Knowledge Base Quality Pack is installed)
- `ghcr.io/yohasebe/monadic-python` (prebuilt default Python image, present when no install options are selected or as a build cache)

#### Volumes

- `monadic-chat-qdrant-data`
- `monadic-chat-embeddings-models`

### Manual Removal Commands :id=manual-removal-commands

To manually remove Docker resources, use the following commands:

```bash
# Remove containers
docker rm -f monadic-chat-ruby-container
docker rm -f monadic-chat-python-container
# ... (repeat for other containers)

# Remove images
docker rmi -f yohasebe/monadic-chat
docker rmi -f yohasebe/python
# ... (repeat for other images)

# Remove volumes
docker volume rm monadic-chat-qdrant-data
docker volume rm monadic-chat-embeddings-models
# Legacy volumes (only present on installs upgraded from older versions)
docker volume rm monadic-chat-pgvector-data 2>/dev/null || true
```

**Note**: On Linux, if you encounter permission errors, prefix the commands with `sudo`. If a container is running and cannot be removed, stop it first with `docker stop <container-name>`.
