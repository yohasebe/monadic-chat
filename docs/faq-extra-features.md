# FAQ: Adding New Features

**Q**: I installed the Ollama plugin and downloaded a model, but it is not reflected in the web interface. What should I do?

**A**: It may take some time for the model downloaded to the Ollama container to be loaded and become available. Wait a while and then reload the web interface. If the downloaded model still does not appear, access the Ollama container from the terminal and run the `ollama list` command to check if the downloaded model is displayed in the list. If it is not displayed, run the `ollama reload` command to reload the Ollama plugin.

**Q**: How can I add new programs or libraries to the Python container?

**A**: There are several ways to do this, but it is convenient to add an installation script to the `pysetup.sh` in the shared folder to install libraries during the Monadic Chat environment setup. See [Adding Libraries](/python-container?id=adding-programs-and-libraries) and [Using pysetup.sh](/python-container?id=usage-of-pysetupsh) for more information.
