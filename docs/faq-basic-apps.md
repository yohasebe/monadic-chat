# FAQ: Basic Applications

**Q**: What is the difference between the `Code Interpreter` app and the `Coding Assistant` and `Jupyter Notebook` apps?

**A**: The `Code Interpreter` app is an application that runs Python scripts using the Python interpreter on the Python container. You can not only ask the AI agent to write Python code but also actually run it and get the results. In addition to Python scripts, you can also read and process CSV files, Microsoft Office files, and audio files (MP3, WAV).

The `Coding Assistant` app provides features to assist in creating various programs (Python, Ruby, JavaScript, etc.). You cannot run code with the AI agent, but you can provide source code and request bug fixes or feature additions.

For a certain range of code bases, it is possible to cache them using the mechanism provided on the API side. You can pass the current source code first and then request modifications one after another.
The `Jupyter Notebook` app uses JupyterLab to write and execute Jupyter Notebook cells. In addition to asking the AI agent to think about the code to enter in the cell, you can create a notebook (`ipynb` file) in a shared folder and add and execute cells one after another. It can be used as a support tool for creating library tutorials or notebooks for programming education.

