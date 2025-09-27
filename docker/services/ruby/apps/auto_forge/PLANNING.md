# AutoForge Planning Document

## Overview
AutoForge is an autonomous software builder that orchestrates multiple agents to create complete applications without repetitive function calls or incomplete implementations.

## Core Architecture

### 1. Directory Structure
```
auto_forge/
├── auto_forge.mdsl          # Main orchestrator DSL
├── auto_forge.rb            # Main Ruby class
├── auto_forge_utils.rb      # Common utilities
├── agents/                  # Specialized agent modules
│   ├── file_generator.rb    # File creation agent
│   ├── code_reviewer.rb     # Code review agent
│   └── test_writer.rb       # Test generation agent
├── PLANNING.md              # This document
└── README.md                # User documentation
```

### 2. Key Components

#### 2.1 Project Directory Management (auto_forge_utils.rb)
```ruby
module AutoForgeUtils
  # Create timestamped project directory
  def self.create_project_directory(base_name)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    safe_name = base_name.gsub(/[^a-zA-Z0-9_-]/, '_')
    project_name = "#{safe_name}_#{timestamp}"

    base_path = File.expand_path("~/monadic/data")
    project_path = File.join(base_path, project_name)

    FileUtils.mkdir_p(project_path)
    { name: project_name, path: project_path }
  end

  # Validate project specification
  def self.validate_spec(spec)
    # Check required fields
    # Validate file list completeness
    # Return validation result
  end
end
```

#### 2.2 State Management
- **Single execution flag**: Prevent multiple forge_project calls
- **Progress tracking**: Real-time updates via Monadic context
- **Completion verification**: Ensure all files are created

#### 2.3 Orchestration Flow
```
1. receive_specification
   ↓
2. validate_and_plan
   ↓
3. create_project_structure
   ↓
4. delegate_to_agents (parallel where possible)
   ↓
5. verify_completeness
   ↓
6. report_results
```

### 3. Agent Design Principles

#### 3.1 Agent Responsibilities
- **FileGenerator**: Creates individual files based on specifications
- **CodeReviewer**: Validates generated code for consistency
- **TestWriter**: Generates appropriate tests for the code

#### 3.2 Agent Communication
- Agents communicate through shared context (@context)
- Results are aggregated in the orchestrator
- No direct agent-to-agent communication

### 4. Safeguards Against Common Issues

#### 4.1 Preventing Repetitive Calls
```ruby
def forge_project(spec)
  return "ALREADY EXECUTED" if @forge_executed
  @forge_executed = true
  # ... actual implementation
end
```

#### 4.2 Ensuring Completeness
```ruby
def verify_all_files_created
  planned_files = @context["planned_files"]
  created_files = @context["created_files"]

  missing = planned_files - created_files
  return { complete: false, missing: missing } if missing.any?

  { complete: true }
end
```

#### 4.3 Error Recovery
- Each agent has retry logic with exponential backoff
- Fallback content generation for critical files
- Clear error reporting to user

### 5. Implementation Phases

#### Phase 1: Basic Structure ✓
- [x] Create directory structure
- [x] Planning document

#### Phase 2: Core Utilities ✓
- [x] Implement auto_forge_utils.rb with project management
- [x] Basic project directory creation with timestamps
- [x] Specification validation
- [x] Encoding helper module (safe UTF-8 handling)
- [x] File operations with verification and rollback
- [x] Directory operations and batch file generation

#### Phase 3: Main Orchestrator
- [ ] Reorganize auto_forge_utils.rb as facade
- [ ] Move project management to utils/project_manager.rb
- [ ] Implement auto_forge.rb class
- [ ] State management
- [ ] Single execution enforcement

#### Phase 4: MDSL Configuration
- [ ] Define tool interfaces
- [ ] System prompts with clear rules
- [ ] Integration with Monadic framework

#### Phase 5: Basic Agent
- [ ] FileGenerator agent
- [ ] Integration with GPT-5-Codex

#### Phase 6: Testing & Refinement
- [x] Unit tests for all utilities (inline)
- [ ] Integration tests
- [ ] Error scenario handling

### 6. Critical Success Factors

1. **Atomic Operations**: All files created in one session
2. **No Repetition**: forge_project can only run once per conversation
3. **Clear Status**: User always knows what's happening
4. **Complete Results**: Never partial implementations
5. **Graceful Failures**: Clear error messages and recovery

### 7. Lessons from Previous Attempts

#### What Failed in CodingAssistantV2
- LLM called same functions repeatedly
- No execution state enforcement
- Unclear completion criteria
- Complex interdependencies

#### How AutoForge Addresses These
- Single execution flag at Ruby level
- Clear "ALREADY EXECUTED" responses
- Deterministic completion verification
- Simplified, linear flow

### 8. Future Extensions

- **Parallel agent execution** for independent tasks
- **Template library** for common project types
- **Integration with external tools** (git, npm, etc.)
- **Progress visualization** in web UI
- **Resume capability** for interrupted builds

## Implementation Progress (2025-01-27)

### ✅ Completed
1. **Utility Modules**
   - `utils/encoding_helper.rb` - UTF-8 handling, line ending normalization
   - `utils/file_operations.rb` - Write/edit/delete with verification, backup, rollback
   - `utils/directory_operations.rb` - Directory structure creation, tree visualization, batch file generation
   - `auto_forge_utils.rb` - Project management, validation

2. **Testing**
   - All modules have inline tests
   - Total: 24 tests, 66 assertions, all passing

### 🔄 In Progress
- Reorganizing auto_forge_utils.rb structure
- Planning main orchestrator implementation

### 📋 TODO (Priority Order)

#### High Priority (Essential)
- [x] Directory structure creation
- [x] Batch file generation
- [x] Directory tree visualization

#### Medium Priority (Important)
- [ ] Template-based file generation
- [ ] Make files executable (chmod +x)
- [ ] README auto-generation

#### Low Priority (Nice to Have)
- [ ] Dependency file updates (package.json, Gemfile)
- [ ] .gitignore management
- [ ] Config file merging
- [ ] Syntax validation
- [ ] Import/export analysis
- [ ] Git integration

## Next Steps

1. ✅ Review and refine this plan
2. ✅ Implement basic utility modules (file/directory operations)
3. 🔄 Implement critical utilities (StateManager, PromptBuilder)
4. [ ] Reorganize auto_forge_utils.rb as facade
5. [ ] Create basic auto_forge.rb with state management
6. [ ] Implement first AI agent (FileGenerator)
7. [ ] Test with simple project generation
8. [ ] Gradually add more specialized agents

## Critical Utilities Status

### Required Before AI Agents
- **StateManager** 📝 Designed, ready for implementation
  - Prevents duplicate execution
  - Tracks generation state
  - Manages locks and history

- **PromptBuilder** 📝 Designed, ready for implementation
  - Template management
  - Context injection
  - Token limit handling

See `UTILITIES_DESIGN.md` for detailed specifications.

---

*Last updated: 2025-01-27 (Active Development)*