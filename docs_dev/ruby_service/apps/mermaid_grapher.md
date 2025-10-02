# Mermaid Grapher: Rendering Notes

## Unicode Normalisation

Mermaid.js expects ASCII arrows (`-->`) and plain quotes inside labels. Recent GPT outputs occasionally include:

- Unicode dashes (`–`, `—`, `ー`, etc.) in place of `-`
- Smart quotes (`“”`, `‘’`, `「」`)
- Full-width slashes (`／`) or repeated blank lines inside brackets

Before validation/rendering we normalise:

- decode any HTML entities returned by the LLM
- replace unicode dashes with `-`
- convert smart quotes / Japanese-style quotes to ASCII
- collapse blank lines inside `[ ... ]` and rewrite line breaks as `\n`

Keep these steps if you touch `sanitize_mermaid_code` or `sanitizeMermaidSource`.

## HTML embedding

When embedding Mermaid code into the preview HTML, we now escape only `<`, `>` and `&`. Quotes stay literal so labels render correctly. Any future change must preserve this behaviour.

## Preview Guard Rails

`preview_mermaid` refuses to run unless the latest `validate_mermaid_syntax` succeeded for the exact same code. Always check `next_action` in tool responses before re-running tools. Workflow:

1. Call `validate_mermaid_syntax` (max 3 retries on failure)
2. Only on `workflow_status: validation_passed` run `preview_mermaid`
3. Use the returned `validated_code` in the final answer

## Frontend helper

`sanitizeMermaidSource` mirrors the backend normalisation so the Mermaid snippet inside `<mermaid>` matches the preview PNG output. If you modify the backend logic, update the frontend helper accordingly.
