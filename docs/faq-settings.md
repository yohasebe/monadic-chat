# FAQ: Setup and Settings

**Q**: Do I need an OpenAI API token to use Monadic Chat?

**A**: An OpenAI API token is not necessarily required if you do not use functions such as speech recognition, speech synthesis, and text embedding. You can also use APIs such as Anthropic Claude, Google Gemini, Cohere, and Mistral AI.

If you do not want to use commercial APIs, you can use the Ollama container. For information on using Ollama with Monadic Chat, see [Using Ollama](./ollama).

---

**Q**: Rebuilding Monadic Chat (rebuilding the containers) fails. What should I do?

**A**: Check the contents of the log files in the shared folder.

If you are developing additional apps or modifying existing apps, check the contents of `server.log` in the log folder. If an error message is displayed, correct the app code based on the error message.

If you are adding libraries to the Python container using `pysetup.log`, error messages may be displayed in `docker_build.log`. Check the error message and correct the installation script.
