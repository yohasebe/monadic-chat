# Monadic Mode

Monadic Mode is a distinctive feature of Monadic Chat that allows you to maintain and update structured context throughout your conversation with AI agents. This enables more coherent and purposeful interactions.

## Overview

In Monadic Mode, each response from the AI includes both a message and a structured context object. This context is preserved and updated throughout the conversation, allowing the AI to maintain state and reference previous information.

### Basic Structure

```json
{
  "message": "The AI's response to the user",
  "context": {
    "key1": "value1",
    "key2": "value2",
    // Additional context fields as needed
  }
}
```

## When Monadic Mode is Used

Monadic Mode is currently used primarily with OpenAI models because it requires reliable structured outputs (JSON format). While there is some experimental implementation for other providers, stable support is currently limited to:

- **OpenAI** - Full support with reliable structured outputs

For providers that don't yet support reliable structured outputs (such as Claude, Gemini, Mistral, and Cohere), Monadic Chat uses an alternative implementation called "toggle mode" to provide similar context management functionality.

?> **Note**: The `monadic` and `toggle` features are mutually exclusive. The appropriate mode is automatically selected based on your chosen provider. Future versions may extend Monadic Mode support to additional providers as their structured output capabilities improve.

## Architecture

The monadic functionality is implemented through several modules:

- **`monadic_unit`**: Wraps messages with context in JSON format
- **`monadic_unwrap`**: Safely extracts data from JSON responses
- **`monadic_map`**: Transforms context with optional processing
- **`monadic_html`**: Renders JSON context as collapsible HTML in the UI

## Practical Examples

### 1. Jupyter Notebook App

The Jupyter Notebook app uses Monadic Mode to track the state of a Python notebook session:

```yaml
# Context structure maintained by the app
context:
  link: "http://localhost:8888/notebooks/analysis.ipynb"
  modules: ["numpy", "pandas", "matplotlib"]
  functions: [{"name": "process_data", "args": ["df", "threshold"]}]
  variables: ["df", "results", "config"]
```

This allows the AI to:
- Reference previously defined variables and functions
- Know which libraries are imported
- Suggest code that builds on previous cells

### 2. Novel Writer App

The Novel Writer app maintains story consistency through structured context:

```yaml
# Context for creative writing
context:
  plot: "A detective story set in Victorian London"
  target_length: 50000
  current_length: 12500
  language: "English"
  summary: "Detective Holmes has discovered the first clue..."
  characters: ["Sherlock Holmes", "Dr. Watson", "Professor Moriarty"]
  question: "How should Holmes proceed with the investigation?"
```

### 3. Language Practice Plus App

For language learning, the context tracks learning progress:

```yaml
# Context for language practice
context:
  target_language: "Japanese"
  advice: 
    - "Consider using 'です/ます' form for politeness"
    - "The particle 'を' is needed after the direct object"
```

## Creating a Monadic App

To create an app that uses Monadic Mode, define it in your MDSL file:

```ruby
app "MyAppOpenAI" do
  description "An app that maintains context"
  icon "fa-brain"
  
  features do
    monadic true  # This is set automatically for OpenAI
    context_size 20
  end
  
  initial_prompt <<~PROMPT
    You are an AI assistant that maintains context.
    
    Return your response in this JSON format:
    {
      "message": "Your response here",
      "context": {
        "state": "current state",
        "data": "accumulated data"
      }
    }
  PROMPT
end
```

## UI Representation

In the web interface, monadic context appears as:
- Collapsible sections showing the context structure
- Empty objects display as ": empty" for clarity
- Field labels are shown with increased font weight
- Missing values shown as "no value" in italic gray text

## Best Practices

1. **Keep context focused**: Only store information that will be referenced later
2. **Use consistent keys**: Maintain the same context structure throughout the conversation
3. **Update incrementally**: Modify only the parts of context that change
4. **Handle errors gracefully**: Always validate context before using it

## Troubleshooting

If context is not updating properly, ensure your initial prompt specifies the expected JSON format and that the AI response includes valid JSON. Keep context objects reasonably sized to avoid issues.

## See Also

- [Monadic DSL](./monadic_dsl.md) - Full MDSL syntax reference
- [Basic Apps](../basic-apps/) - Examples of apps using Monadic Mode