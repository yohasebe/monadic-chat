# GPT-5-Codex Agent Integration

## Overview

GPT-5-Codex is a specialized OpenAI model optimized for code generation and complex programming tasks. Monadic Chat integrates GPT-5-Codex as an agent model that can be called from several OpenAI-based applications.

## Supported Applications

The following OpenAI applications can leverage GPT-5-Codex for complex coding tasks:

### 1. Coding Assistant
Delegates complex coding tasks to GPT-5-Codex while maintaining file I/O capabilities:
- Writing complete applications
- Code refactoring and optimization
- Debugging and error fixing
- Performance improvements

### 2. Code Interpreter
Uses GPT-5-Codex for Python code generation:
- Complex algorithm implementation
- Data analysis scripts
- Visualization code
- Error diagnosis and fixing

### 3. Jupyter Notebook
Leverages GPT-5-Codex for notebook cell generation:
- Data analysis pipelines
- Machine learning workflows
- Scientific computing code
- Notebook optimization

### 4. Research Assistant
Employs GPT-5-Codex for analysis code generation:
- Data collection scripts
- Statistical analysis code
- API client implementation
- Research data processing

## How It Works

1. **User Interaction**: You interact with the main model (GPT-5)
2. **Task Delegation**: When the main model identifies a complex coding task, it automatically delegates to GPT-5-Codex
3. **Code Generation**: GPT-5-Codex generates high-quality code based on the task
4. **Result Integration**: The main model receives the code and integrates it into the workflow

## Requirements

- OpenAI API key with access to GPT-5-Codex
- The feature is automatically available in supported applications

## Usage Example

When using Coding Assistant or Code Interpreter, simply describe your coding task. The application will automatically determine when to use GPT-5-Codex for optimal results:

```
User: "Create a complex data visualization with multiple subplots"
Assistant: [Automatically delegates to GPT-5-Codex for complex matplotlib code]
```

## Technical Notes

- GPT-5-Codex uses the Responses API with adaptive reasoning
- Maximum context window: 400,000 tokens
- Maximum output: 128,000 tokens
- No temperature or sampling parameters (uses deterministic generation)
- Default timeout: 300 seconds (configurable via `GPT5_CODEX_TIMEOUT` environment variable)
- Automatic access checking before delegation
- Message format abstraction for compatibility

## Troubleshooting

If you encounter issues with GPT-5-Codex:
1. **Access Denied**: Ensure your OpenAI API key has access to GPT-5-Codex model
2. **Timeout Errors**: For long-running tasks, increase timeout via `GPT5_CODEX_TIMEOUT` environment variable
3. **Empty Responses**: Try breaking complex tasks into smaller, more specific pieces
4. **Application Not Supported**: Verify you're using Coding Assistant, Code Interpreter, Jupyter Notebook, or Research Assistant

For technical implementation details, developers can refer to the internal documentation.