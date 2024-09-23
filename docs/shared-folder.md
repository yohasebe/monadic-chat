# Shared Folder

This document explains how to set up a folder for sharing files within Docker containers in Monadic Chat.

When you first start Monadic Chat, a `~/monadic/data` directory is created. This directory is the default shared folder for sharing files within Monadic Chat's Docker containers.

Clicking the `Shared Folder` button in the Monadic Chat console will launch the OS's standard file manager and open the shared folder.

By placing files in this directory, you can access those files within Monadic Chat's Docker containers. The path to the shared folder within each Docker container is `/monadic/data`.

In apps that can execute code (e.g., Code Interpreter app), you can read files from the shared folder. When specifying a file, only specify the file name without the directory.

If any processing is done within the app, intermediate files may be saved in the shared folder. If processing fails for some reason, you can check the shared folder to see the intermediate results.

By using the `Actions/Start JupyterLab` menu in the Monadic Chat console, you can start JupyterLab, which will launch with `/monadic/data` as the home directory. This allows you to access files in the shared folder within JupyterLab.

## Automatically Created Subfolders

This section explains the subfolders that are automatically created within Monadic Chat's Docker containers.

**`apps`**

A folder for storing additional applications other than the basic apps.

**`scripts`**

A folder for storing scripts to be executed within the container for use by additional applications.

**`services`**

A folder for storing Docker-related files to create images and containers for use by additional applications.

**`helpers`**

A folder for storing helper files that contains functions (methods) to use in apps.
