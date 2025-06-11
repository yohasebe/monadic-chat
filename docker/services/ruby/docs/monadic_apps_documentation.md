# Monadic Apps Documentation

## Overview

This document provides detailed documentation of the existing monadic applications in Monadic Chat, analyzing their behaviors, dependencies, and implementation patterns.

## Current Monadic Apps (6 total)

All monadic apps currently use OpenAI as the provider and rely on its structured output feature.

### 1. Chat Plus (chat_plus_openai.mdsl)

**Purpose**: Enhanced chat with reasoning tracking and context management

**Monadic Structure**:
```json
{
  "message": "AI response text",
  "context": {
    "reasoning": "The thought process behind the response",
    "topics": ["array of discussed topics"],
    "people": ["array of mentioned people and relationships"],
    "notes": ["array of important information to remember"]
  }
}
```

**Key Features**:
- Uses JSON schema with strict validation
- Accumulates context across conversation
- Preserves all historical context items unless explicitly asked to remove

**Dependencies**:
- OpenAI's `response_format` with `json_schema`
- Strict schema validation

### 2. Jupyter Notebook (jupyter_notebook_openai.mdsl)

**Purpose**: Manage Jupyter notebook creation and execution with state tracking

**Monadic Structure**:
```json
{
  "message": "Response to user",
  "context": {
    "jupyter_running": true,
    "notebook_created": true,
    "link": "<a href='...'>notebook_filename.ipynb</a>",
    "modules": ["imported modules"],
    "functions": ["defined functions"],
    "variables": ["tracked variables"]
  }
}
```

**Key Features**:
- Tracks JupyterLab state across messages
- Monitors imported modules and defined entities
- Prevents re-initialization by checking context state

**Dependencies**:
- Basic JSON output mode (no strict schema)
- Relies on consistent JSON structure from prompt

### 3. Language Practice Plus (language_practice_plus_openai.mdsl)

**Purpose**: Language learning with detailed feedback and progress tracking

**Monadic Structure**:
```json
{
  "message": "Corrected text or response",
  "context": {
    "original": "User's original input",
    "corrected": "Grammatically correct version",
    "errors": [
      {
        "type": "grammar|spelling|usage|style",
        "original": "error text",
        "correction": "correct text",
        "explanation": "why it's wrong"
      }
    ],
    "learning_notes": ["cumulative learning points"],
    "level_assessment": "beginner|intermediate|advanced"
  }
}
```

**Key Features**:
- Detailed error analysis with explanations
- Cumulative learning notes
- Level tracking across conversation

**Dependencies**:
- Basic JSON output mode
- Complex nested structure in context

### 4. Novel Writer (novel_writer_openai.mdsl)

**Purpose**: Collaborative novel writing with story state management

**Monadic Structure**:
```json
{
  "message": "Story content or response",
  "context": {
    "title": "Novel title",
    "summary": "Current story summary",
    "characters": {
      "character_name": {
        "description": "...",
        "relationships": {},
        "development": "..."
      }
    },
    "plot_points": ["major events"],
    "current_scene": "scene description",
    "themes": ["story themes"],
    "writing_style": "style notes"
  }
}
```

**Key Features**:
- Complex nested character tracking
- Plot and theme management
- Writing style consistency

**Dependencies**:
- JSON schema with strict validation
- Deep nesting support

### 5. Translate (translate_openai.mdsl)

**Purpose**: Translation with context preservation

**Monadic Structure**:
```json
{
  "message": "Translated text",
  "context": {
    "source_language": "detected or specified",
    "target_language": "translation target",
    "original_text": "source text",
    "alternatives": ["other possible translations"],
    "notes": "translation notes or explanations"
  }
}
```

**Key Features**:
- Language detection
- Alternative translations
- Translation notes

**Dependencies**:
- Basic JSON output mode
- Simple flat structure

### 6. Voice Interpreter (voice_interpreter_openai.mdsl)

**Purpose**: Voice transcription with context awareness

**Monadic Structure**:
```json
{
  "message": "Interpreted response",
  "context": {
    "original_transcript": "raw voice input",
    "interpreted_text": "cleaned up version",
    "confidence": 0.95,
    "ambiguities": ["unclear parts"],
    "conversation_context": "ongoing topic tracking"
  }
}
```

**Key Features**:
- Transcription confidence tracking
- Ambiguity detection
- Context-aware interpretation

**Dependencies**:
- Basic JSON output mode
- Voice-specific context fields

## Common Patterns

### 1. Context Accumulation
- Chat Plus, Language Practice Plus, and Novel Writer accumulate context
- Items are added to arrays, not replaced
- Explicit user request required to clear context

### 2. State Tracking
- Jupyter Notebook and Voice Interpreter track session state
- Boolean flags prevent re-initialization
- State persists across messages

### 3. Structured Feedback
- Language Practice Plus provides detailed error analysis
- Translate offers alternatives
- All apps separate response from metadata

## Technical Dependencies

### OpenAI-Specific Features
1. **response_format parameter**: All apps rely on this
2. **JSON mode**: Ensures valid JSON output
3. **JSON schema**: Used by Chat Plus and Novel Writer for validation

### Monadic Method Usage
1. **monadic_unit**: Wraps user input with existing context
2. **monadic_unwrap**: Parses JSON response safely
3. **monadic_map**: Updates context with new information
4. **monadic_html**: Renders context as collapsible HTML sections

## Migration Considerations

To make these apps work with other providers:

1. **Remove dependency on response_format**: Need alternative JSON enforcement
2. **Simplify schemas**: Complex nesting may not be reliable
3. **Add validation**: Without strict schemas, need post-processing validation
4. **Enhance prompts**: More explicit JSON formatting instructions

## Next Steps

1. Create provider-agnostic monadic base class
2. Implement JSON validation layer
3. Design fallback strategies for non-JSON responses
4. Test with multiple providers