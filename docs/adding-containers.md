# Adding Docker Containers

?> The program examples shown on this page directly reference the code in the [monadic-chat](https//github.com/yohasebe/monadic-chat) repository (`main` branch) on GitHub. If you find any issues, please submit a pull request.

## How to Add Containers

To make a new Docker container available, create a new folder within `~/monadic/data/services` and place the following files inside the new folder:

- `compose.yml`
- `Dockerfile`

To add a container, you need to rebuild Monadic Chat. During this process, a `docker-compose.yml` file will be automatically generated in the `~/monadic/data` directory. This file is used to manage the containers, including starting and removing them.  Avoid manually modifying or deleting this file.

## Example of Necessary Files

As a reference, here are the `compose.yml` and `Dockerfile` for the Python container that is included by default.  In `compose.yml`, you'll add the name of your new container under `services` (e.g., `my_new_service`) and then provide the necessary configuration details below it.  Files to be copied within the `Dockerfile` should be placed in the same directory as the `compose.yml` and `Dockerfile`.

### compose.yml

<details open="true">
<summary>compose.yml</summary>

[compose.yml](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/python/compose.yml ':include :type=code')

</details>

### Dockerfile

In the `Dockerfile`, describe how to build the new container.

<details open="true">
<summary>Dockerfile</summary>

[Dockerfile](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/python/Dockerfile ':include :type=code dockerfile')

</details>
