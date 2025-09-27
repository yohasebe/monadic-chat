# AutoForge Critical Utilities Design

## Overview

Before implementing AI agents, we need robust utilities to control and manage their execution. This document outlines the two most critical utilities: StateManager and PromptBuilder.

## 1. StateManager - Execution State Management

### Purpose
Prevent duplicate execution and track project generation state across multiple AI agent calls.

### Problem It Solves
- AI agents repeatedly calling the same function (e.g., CodingAssistantV2's infinite loops)
- Loss of track of what has been generated
- Inability to resume interrupted operations
- No clear error attribution

### Core Concepts

#### 1.1 Locks
Prevent concurrent or duplicate execution of the same task.

```ruby
# Example: Preventing duplicate file generation
lock = StateManager.acquire_lock(project_id, "generate_index_html")
if lock[:success]
  # Safe to proceed
else
  # Already running - skip or wait
end
```

#### 1.2 Artifacts Registry
Track all generated files and their metadata.

```ruby
StateManager.record_artifact(project_id, file_path, {
  generator: "html_agent",
  tokens_used: 1250,
  generation_time: 2.3
})
```

#### 1.3 Execution History
Maintain audit trail of all operations.

```ruby
StateManager.log_execution(project_id,
  action: "generate_file",
  target: "index.html",
  result: "success",
  duration: 2.3
)
```

### Implementation Structure

```ruby
module StateManager
  class State
    attr_accessor :locks, :history, :artifacts, :metadata

    def initialize
      @locks = {}      # Currently held locks
      @history = []    # Execution history
      @artifacts = {}  # Generated files registry
      @metadata = {}   # Project metadata
    end
  end

  # Key Methods:
  # - init_project(project_id)
  # - acquire_lock(project_id, resource, timeout: 300)
  # - release_lock(project_id, resource)
  # - record_artifact(project_id, path, metadata)
  # - already_generated?(project_id, path)
  # - log_execution(project_id, action, result)
  # - get_project_state(project_id)
  # - cleanup_expired_locks(project_id)
end
```

### Benefits
1. **Idempotency** - Same operation can be called multiple times safely
2. **Recovery** - Can resume from interruption
3. **Debugging** - Clear audit trail
4. **Performance** - Skip regeneration of existing files

## 2. PromptBuilder - Intelligent Prompt Construction

### Purpose
Generate consistent, high-quality prompts for different types of AI agents with proper context injection.

### Problem It Solves
- Vague or inconsistent prompts leading to poor output
- Loss of project context between agent calls
- Token limit exceeded errors
- Lack of reusable prompt patterns

### Core Concepts

#### 2.1 Template Management
Pre-defined templates for each agent type.

```ruby
TEMPLATES = {
  html_generator: "structured HTML generation template...",
  js_generator: "JavaScript generation template...",
  css_generator: "CSS generation template..."
}
```

#### 2.2 Context Injection
Dynamic insertion of project-specific information.

```ruby
context = {
  project_name: "Calculator",
  tech_stack: "React + TypeScript",
  existing_files: ["package.json", "tsconfig.json"],
  style_guide: "Material Design"
}

prompt = PromptBuilder.build(:react_component, context)
```

#### 2.3 Token Management
Ensure prompts fit within model limits.

```ruby
def ensure_within_limit(prompt, max_tokens)
  if exceeds_limit?(prompt, max_tokens)
    prioritize_and_truncate(prompt, max_tokens)
  end
end
```

### Implementation Structure

```ruby
module PromptBuilder
  # Template storage
  TEMPLATES = {
    html_generator: ERB.new(HTML_TEMPLATE),
    js_generator: ERB.new(JS_TEMPLATE),
    css_generator: ERB.new(CSS_TEMPLATE),
    # ... more templates
  }

  # Key Methods:
  # - build(agent_type, context)
  # - build_project_context(project_spec)
  # - format_related_files(files)
  # - ensure_within_limit(prompt, max_tokens)
  # - adjust_for_complexity(prompt, level)
  # - add_examples(prompt, examples)
  # - add_constraints(prompt, constraints)
end
```

### Template Example

```erb
Generate <%= file_type %>: <%= file_name %>

Project Context:
- Name: <%= project_name %>
- Stack: <%= tech_stack %>
- Purpose: <%= description %>

Existing Files:
<%= existing_files.map { |f| "- #{f}" }.join("\n") %>

Requirements:
<%= requirements.map { |r| "- #{r}" }.join("\n") %>

Constraints:
- Output only code, no explanations
- Follow <%= style_guide %> conventions
- Ensure compatibility with <%= dependencies %>

<% if examples.any? %>
Examples:
<%= format_examples(examples) %>
<% end %>
```

### Advanced Features

#### Dynamic Complexity Adjustment
```ruby
def adjust_for_complexity(base_prompt, complexity)
  case complexity
  when :simple
    base_prompt + "\nPrioritize simplicity and readability."
  when :production
    base_prompt + "\nInclude error handling, logging, and optimization."
  end
end
```

#### Chain-of-Thought Prompting
```ruby
def add_reasoning_steps(prompt, task_type)
  prompt + "\n\nThink step-by-step:\n" +
  REASONING_STEPS[task_type].join("\n")
end
```

### Benefits
1. **Consistency** - Same quality across all generations
2. **Flexibility** - Easy to adjust for different projects
3. **Reusability** - Templates can be refined and shared
4. **Control** - Fine-grained control over AI behavior

## 3. Integration Example

How StateManager and PromptBuilder work together:

```ruby
class AutoForge
  def generate_file(project_id, file_spec)
    # 1. Check if already generated (StateManager)
    if StateManager.already_generated?(project_id, file_spec[:path])
      return { status: "skipped", reason: "already exists" }
    end

    # 2. Acquire lock (StateManager)
    lock = StateManager.acquire_lock(project_id, file_spec[:path])
    return { status: "locked" } unless lock[:success]

    begin
      # 3. Build prompt (PromptBuilder)
      context = StateManager.get_project_state(project_id)
      prompt = PromptBuilder.build(file_spec[:type], context)

      # 4. Call AI agent
      content = call_ai_agent(prompt)

      # 5. Write file
      write_file(file_spec[:path], content)

      # 6. Record success (StateManager)
      StateManager.record_artifact(project_id, file_spec[:path])
      StateManager.log_execution(project_id, "generate", "success")

    ensure
      # 7. Release lock
      StateManager.release_lock(project_id, file_spec[:path])
    end
  end
end
```

## 4. Other Important Utilities

### High Priority
1. **ErrorRecovery** - Handle and recover from AI failures
2. **TaskDecomposer** - Break large tasks into manageable pieces
3. **AgentCommunication** - Coordinate multiple agents

### Medium Priority
4. **CodeValidator** - Syntax and security checks
5. **DependencyManager** - Track and resolve dependencies
6. **ResultFormatter** - Standardize output format

### Nice to Have
7. **CacheManager** - Reuse previous generations
8. **MetricsCollector** - Track performance and costs
9. **VersionControl** - Track changes and rollback

## 5. Implementation Order

1. **Phase 1**: StateManager (critical for preventing duplicates)
2. **Phase 2**: PromptBuilder (critical for quality)
3. **Phase 3**: ErrorRecovery (handle failures gracefully)
4. **Phase 4**: Other utilities as needed

## 6. Testing Strategy

Each utility should have:
- Unit tests for core functionality
- Integration tests with mock agents
- Stress tests for concurrent operations
- Failure scenario tests

Example test:

```ruby
class StateManagerTest < Minitest::Test
  def test_prevents_duplicate_execution
    StateManager.init_project("test_123")

    # First lock succeeds
    lock1 = StateManager.acquire_lock("test_123", "file.txt")
    assert lock1[:success]

    # Second lock fails (duplicate prevention)
    lock2 = StateManager.acquire_lock("test_123", "file.txt")
    refute lock2[:success]
    assert_equal "Task already running", lock2[:message]
  end
end
```

## 7. Success Criteria

- **StateManager**: Zero duplicate file generations
- **PromptBuilder**: 90%+ success rate on first generation
- **Combined**: Complete project generation without manual intervention

---

*Last updated: 2025-01-27*
*Status: Design Phase - Ready for Implementation*