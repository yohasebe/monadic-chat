# Uninstallation

## Basic Steps

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

<img src="../assets/images/monadic-chat-menu.png" width="250px"/>

## Cleanup (Optional)

If the containers and images are not deleted even after running `Uninstall Images and Containers`, or if problems occur during an update or uninstallation, manually delete the following Docker containers and images and then reinstall Monadic Chat.

### Docker Containers and Images

#### Containers

- `monadic-chat-container`
    - `monadic-chat-ruby-container`
    - `monadic-chat-python-container`
    - `monadic-chat-selenium-container`
    - `monadic-chat-pgvector-container`

#### Images

- `yohasebe/monadic-chat`
- `yohasebe/python`
- `yohasebe/selenium`
- `yohasebe/pgvector`
