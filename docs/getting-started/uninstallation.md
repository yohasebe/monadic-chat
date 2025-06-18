# Uninstallation

## Basic Steps :id=basic-steps

The basic steps to uninstall Monadic Chat are as follows:

- Exit Monadic Chat
- Delete Docker containers and images
- Uninstall Monadic Chat

<!-- tabs:start -->

### **macOS**

1. Run `Uninstall Images and Containers` from the menu. This will delete the Docker containers and images shown below.
2. Exit Monadic Chat.
3. Open the `Applications` folder in Finder and drag Monadic Chat to the trash.

### **Windows**

1. Run `Uninstall Images and Containers` from the menu. This will delete the Docker containers and images shown below.
2. Exit Monadic Chat.
3. Uninstall Monadic Chat from `Add or Remove Programs`.

### **Linux**

1. Run `Uninstall Images and Containers` from the menu. This will delete the Docker containers and images shown below.
2. Exit Monadic Chat.
3. Run the following command in the terminal.

```shell
$ sudo apt remove monadic-chat
```

<!-- tabs:end -->

![](../assets/images/monadic-chat-menu.png ':size=250')

## User Data :id=user-data

After uninstallation, your personal data and settings remain in the following directory:
- `~/monadic/` (macOS/Linux) or `%USERPROFILE%\monadic\` (Windows)

This includes your configuration files, chat logs, and any generated data. You can manually delete this directory if you want to completely remove all traces of Monadic Chat.

## Cleanup (Optional) :id=cleanup

If the containers and images are not deleted even after running `Uninstall Images and Containers`, or if problems occur during an update or uninstallation, you have two options:

### Option 1: Clean/Purge All Docker Data :id=clean-purge-docker-data

You can use Docker Desktop's menu: `Troubleshoot` → `Clean/Purge data` to remove all Docker images and containers. **Warning**: This will remove ALL Docker data on your system, including data from other applications, not just Monadic Chat's.

### Option 2: Manual Removal :id=manual-removal

Alternatively, you can manually delete only the Monadic Chat-related Docker containers and images:

### Docker Containers and Images :id=docker-containers-images

#### Containers

- `monadic-chat-ruby-container`
- `monadic-chat-python-container`
- `monadic-chat-selenium-container`
- `monadic-chat-pgvector-container`
- `monadic-chat-ollama-container` (if Ollama is installed)
- `monadic-chat-web-container` (legacy)
- `monadic-chat-container` (legacy)

#### Images

- `yohasebe/monadic-chat`
- `yohasebe/python`
- `yohasebe/selenium`
- `yohasebe/pgvector`
- `yohasebe/ollama` (if Ollama is installed)

#### Volumes

- `monadic-chat-pgvector-data`

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
docker volume rm monadic-chat-pgvector-data
```

**Note**: On Linux, if you encounter permission errors, prefix the commands with `sudo`. If a container is running and cannot be removed, stop it first with `docker stop <container-name>`.
