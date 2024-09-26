# Adding Docker Containers

## How to Add Containers

To make a new Docker container available, create a new folder in `~/monadic/data/services` and place the following files inside it:

- `compose.yml`
- `Dockerfile`

To add a container, you need to rebuild Monadic Chat. During this process, a `docker-compose.yml` file will be automatically generated in the `~/monadic/data` directory. This file is also used to remove images and containers, so you should generally avoid manual changes or deletions.

## Example of Necessary Files

As a reference, here are the `compose.yml` and `Dockerfile` for the Python container that is included by default. In `compose.yml`, add the name of the new container under `services`. Files to be copied in the Dockerfile should be placed in the same directory as `compose.yml` and `Dockerfile`.

### compose.yml

<details open="true">
<summary>compose.yml</summary>

[compose.yml](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/python/compose.yml ':include :type=code')

</details>

### Dockerfile

In the `Dockerfile`, describe how to build the new container. 

<details open="true">
<summary>Dockerfile</summary>

[Dockerfile](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/nightly/docker/services/python/Dockerfile ':include :type=code dockerfile')

</details>
