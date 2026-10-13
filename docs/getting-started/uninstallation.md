# Uninstallation

## Basic Steps :id=basic-steps

The basic steps to uninstall Monadic Chat are as follows:

- Delete Monadic Chat's Docker containers and images from its menu
- Exit Monadic Chat
- Uninstall Monadic Chat

<!-- tabs:start -->

### **macOS**

1. Choose `Remove Images/Containers/Data` in the File menu (the Monadic Chat menu). This deletes Monadic Chat's Docker containers, images and volumes (the Knowledge Base data), listed below. Your files in `~/monadic` are kept.
2. Exit Monadic Chat.
3. Open the `Applications` folder in Finder and drag Monadic Chat to the trash.

### **Windows**

1. Choose `Remove Images/Containers/Data` in the File menu. This deletes Monadic Chat's Docker containers, images and volumes (the Knowledge Base data), listed below. Your files in `~/monadic` are kept.
2. Exit Monadic Chat.
3. Uninstall Monadic Chat in Windows Settings, under Apps.

### **Linux**

1. Choose `Remove Images/Containers/Data` in the File menu. This deletes Monadic Chat's Docker containers, images and volumes (the Knowledge Base data), listed below. Your files in `~/monadic` are kept.
2. Exit Monadic Chat.
3. Delete the AppImage file you downloaded.

Monadic Chat ships as an AppImage, which is never installed into the system, so there is no package to remove:

```shell
$ rm monadic-chat_*.AppImage
```

If your desktop environment offered to integrate the AppImage into your application menu, remove the entry it created (usually under `~/.local/share/applications/`).

<!-- tabs:end -->

<!-- SCREENSHOT: Monadic Chat menu showing the File menu with the Remove Images/Containers/Data option -->

## User Data :id=user-data

After uninstallation, your data and settings remain in two places:

- `~/monadic/`: configuration files, the shared folder and logs. On Windows, this folder is in the home folder of your WSL Linux (Ubuntu), not in Windows
- The application's own storage (cookies, cached pages, window state):
  - macOS: `~/Library/Application Support/Monadic Chat`
  - Linux: `~/.config/Monadic Chat`
  - Windows: `%APPDATA%\Monadic Chat`

Delete both folders to remove Monadic Chat's data and settings.

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
- `ghcr.io/yohasebe/monadic-python` (downloaded as a build cache for the Python container)

#### Volumes

- `monadic-chat-qdrant-data`

### Manual Removal Commands :id=manual-removal-commands

To manually remove Docker resources, use the following commands:

```bash
# Remove containers
docker rm -f monadic-chat-ruby-container
docker rm -f monadic-chat-python-container
# ... (repeat for other containers)

# Remove images (every tag of each)
docker rmi -f $(docker images -q yohasebe/monadic-chat)
docker rmi -f $(docker images -q yohasebe/python)
# ... (repeat for other images)

# Remove volumes
docker volume rm monadic-chat-qdrant-data
```

**Note**: On Linux, if you encounter permission errors, prefix the commands with `sudo`. If a container is running and cannot be removed, stop it first with `docker stop <container-name>`.
