# MCP Tool Reference

This document provides a quick reference for commonly used MCP tools in Monadic Chat.

## Help System Tools

### MonadicHelpOpenAI__find_help_topics
Search Monadic Chat documentation.

**Parameters:**
- `text` (string, required): Search query text
- `top_n` (integer, optional): Number of results to return (default: 5)
- `chunks_per_result` (integer, optional): Number of text chunks per document (default: 3)

**Example:**
```json
{
  "name": "MonadicHelpOpenAI__find_help_topics",
  "arguments": {
    "text": "syntax tree",
    "top_n": 3
  }
}
```

### MonadicHelpOpenAI__get_help_document
Retrieve full content of a help document by ID.

**Parameters:**
- `doc_id` (integer, required): Document ID to retrieve

## PDF Navigation Tools

### PDFNavigatorOpenAI__search_pdf
Search within PDF documents.

**Parameters:**
- `query` (string, required): Search query
- `top_n` (integer, optional): Number of results (default: 10)

## Code Execution Tools

### CodeInterpreterOpenAI__run_code
Execute code in various programming languages.

**Parameters:**
- `language` (string, required): Programming language (python, ruby, javascript, etc.)
- `code` (string, required): Code to execute

## Image Generation Tools

### ImageGeneratorOpenAI__dall_e_3
Generate images using DALL-E 3.

**Parameters:**
- `prompt` (string, required): Image description
- `size` (string, optional): Image size (1024x1024, 1792x1024, 1024x1792)
- `quality` (string, optional): Image quality (standard, hd)

## Syntax Tree Tools

### SyntaxTreeOpenAI__render_syntax_tree
Generate linguistic syntax trees.

**Parameters:**
- `sentence` (string, required): Sentence to analyze
- `language` (string, optional): Language of the sentence

## Video Analysis Tools

### VideoDescriberApp__analyze_video
Analyze video content.

**Parameters:**
- `video_path` (string, required): Path to video file
- `max_frames` (integer, optional): Maximum frames to analyze

## Tips for MCP Clients

1. Always check the `inputSchema` in the tools/list response for accurate parameter information
2. Required parameters are listed in the `required` array
3. Parameter types are specified in the `properties` object
4. Use the exact parameter names as specified in the schema (e.g., `text` not `query` for help search)