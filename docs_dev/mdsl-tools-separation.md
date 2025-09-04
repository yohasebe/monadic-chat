# MDSL and Tools File Separation

## Overview

This document describes the architecture for separating MDSL-generated app classes from their tool modules to prevent duplicate class definitions.

## Problem

Previously, both MDSL files and tools files could define app classes, leading to:
- Duplicate class definitions
- Settings being overwritten
- Apps appearing with incorrect display names and groups

## Solution Architecture

### MDSL Files (*.mdsl)

MDSL files define app configurations declaratively and generate classes automatically:
- Located in: `apps/[app_name]/[app_name]_[provider].mdsl`
- Purpose: Define app settings, prompts, features, and LLM configurations
- Output: Generates Ruby classes inheriting from MonadicApp

### Tools Files (*_tools.rb)

Tools files provide shared functionality as modules:
- Located in: `apps/[app_name]/[app_name]_tools.rb`
- Purpose: Define shared methods, utilities, and tool integrations
- Pattern:

```ruby
# Shared tools module for [App Name] apps
# This module is automatically included by MDSL-generated classes
# Note: Class definitions are handled by MDSL files, not here

module [AppName]Tools
  # Shared functionality here
end
```

## Implementation Details

### MDSL Loader Behavior

1. MDSL files are processed by `MonadicDSL::Loader`
2. Classes are generated with appropriate settings
3. Tools modules are automatically included if they exist
4. The pattern `[AppName]Tools` is detected and included

### Module Naming Convention

- App class: `JupyterNotebookOpenAI`
- Tools module: `JupyterNotebookTools`
- The module name is derived by removing the provider suffix and adding "Tools"

### Loading Order

1. Load all `.rb` files first (including tools modules)
2. Load all `.mdsl` files (which require and include tools modules)
3. Initialize apps from loaded classes

## Migration Guide

When converting existing tools files:

1. Remove all class definitions (e.g., `class AppNameProvider < MonadicApp`)
2. Create a module named `[AppName]Tools`
3. Move all methods and functionality into the module
4. Ensure helper modules are included in the module if needed
5. Add standard header comment explaining the separation

## Benefits

- No duplicate class definitions
- Clear separation of concerns
- Settings are properly preserved
- Apps display correctly in the UI
- Easier maintenance and debugging

## Testing

Verify successful migration by:
1. Checking for duplicate class warnings: `ruby -e "require './lib/monadic.rb'" 2>&1 | grep WARNING`
2. Ensuring all apps appear in correct provider groups
3. Verifying display names are correct (not auto-generated with spaces)