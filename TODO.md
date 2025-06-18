# Monadic Chat TODO List

## Documentation Updates

### Pending Documentation Reviews
- [ ] Review remaining basic-usage documentation files for implementation mismatches
- [ ] Review advanced-topics documentation for accuracy
- [ ] Ensure all Japanese translations are synchronized with English versions
- [x] Add disk space requirements to installation documentation (Docker images, containers, etc.)

### Completed Documentation Fixes
- [x] Fix incorrect Second Opinion app availability (showed only OpenAI, now shows all 9 providers)
- [x] Keep gpt-image-1 as the correct model name for OpenAI image generation (dall-e models are being deprecated)
- [x] Add PDF Navigator database name "monadic_user_docs"
- [x] Add Jupyter security warning for Server Mode
- [x] Update Mistral AI image support to include Pixtral and Mistral Medium 2505
- [x] Confirm Perplexity AI already has image support implemented

### Image/PDF Upload Support Verification
- [x] Verify Perplexity AI image support - already implemented (auto-switches to grok-2-vision-1212)
- [ ] Confirm PDF support accuracy - verify which OpenAI models actually support PDF (gpt-3.5 is deprecated, focus on current models)
- [x] Check Mistral image support scope - Pixtral models and Mistral Medium 2505 support vision
- [ ] Investigate Ollama vision model support (llava, bakllava, etc.) and update documentation accordingly
  - Research required models: llava, llava-llama3, bakllava, moondream
  - Check if ollama_helper.rb needs image support implementation
  - Update model_spec.js with vision_capability for Ollama vision models
  - Note: Testing requires significant local resources

## CONFIG vs ENV Standardization
- [x] Fix OpenAI helper to use CONFIG first, then ENV
- [x] Update second_opinion_agent.rb to use CONFIG for AI_USER_MAX_TOKENS
- [x] Update WEBSEARCH_MODEL usage to check CONFIG first
- [x] Update JUPYTER_PORT usage to check CONFIG first
- [x] Update PYTHON_PORT usage to check CONFIG first
- [x] Update all default model lookups to use CONFIG first

## Documentation Consistency
- [x] Fix "three different modes" inconsistency in web-interface.md
- [x] Update environment variables to configuration variables terminology
- [x] Fix Max Output Tokens description inconsistency
- [x] Separate Browser Modes from Application Modes properly
- [x] Fix image attachment dialog label inconsistency in message-input.md

## Server Mode Security
- [x] Implement ALLOW_JUPYTER_IN_SERVER_MODE configuration variable
- [ ] Document all security implications of Server Mode
- [ ] Consider additional security restrictions for Server Mode
- [ ] Add warning messages for potentially risky configurations

## Database Configuration
- [x] Rename PDF Navigator database from "monadic" to "monadic_user_docs"
- [ ] Document database naming conventions
- [ ] Consider database migration scripts for existing installations

## Future Enhancements
- [ ] Consider implementing a unified configuration helper method
- [ ] Document which variables should be in CONFIG vs ENV
- [ ] Add validation for configuration variable types and values
- [ ] Improve compose.yml auto-generation documentation
- [ ] Add configuration variable validation on startup
- [ ] Make Monadic Chat Help work with non-OpenAI embedding models
  - Currently fixed to text-embedding-3-large (OpenAI)
  - Consider supporting other providers' embedding models
  - Would require changes to help system architecture

## Documentation Structure Improvements
- [ ] **Section ID Standardization**: Add comprehensive section IDs to all documentation files
  - ✅ Completed: web-interface.md, installation.md, message-input.md, uninstallation.md, basic-architecture.md, development_workflow.md, help-system.md, all FAQ files (English/Japanese)
  - [ ] Ensure consistent kebab-case naming pattern for all section IDs
  - [ ] Verify internal links use correct section IDs

## Regular Documentation Maintenance (Recurring Tasks)
- [ ] **Disk Space Requirements**: Regularly check Docker image sizes and update installation documentation
  - Check `docker images` output for yohasebe/* images
  - Update system requirements in installation.md (both English/Japanese)
  - Current baseline: ~12GB for Docker images (as of 2025-01-18)
- [ ] **Provider Model Information**: Keep model lists and capabilities up to date
  - Review model_spec.js for new models and parameter changes
  - Update language-models.md documentation
  - Check provider documentation for new models and deprecations
  - Update basic-apps.md provider compatibility matrices
- [ ] **App Information Updates**: Maintain current app descriptions and availability
  - Review app descriptions in basic-apps.md for accuracy
  - Update provider support matrices when new apps are added
  - Ensure app icons and screenshots are current
  - Check for deprecated or renamed apps
- [ ] **API Changes Monitoring**: Track provider API updates that affect documentation
  - Monitor reasoning_effort parameter changes across providers
  - Track new features like vision capabilities, tool calling support
  - Update provider-specific limitations and requirements

## Research Platform Vision
- [ ] Create comprehensive documentation on "Computational Foundations of Conversation"
  - Explain the monadic approach to conversation state management
  - Document how JSON objects track discourse structure
  - Provide examples of linguistic/cognitive research applications
- [ ] Develop research-oriented documentation section
  - Discourse analysis capabilities (turn-taking, repair organization)
  - Pragmatics research tools (context-dependent meaning)
  - Cognitive science applications (theory of mind, joint attention)
  - Computational linguistics features (formal semantics, knowledge representation)
- [ ] Create API documentation for researchers
  - How to extract conversation data for analysis
  - Methods for tracking state changes and context updates
  - Tools for visualizing dialogue structure
- [ ] Add examples of interdisciplinary research use cases
  - Language acquisition studies
  - Human-AI interaction patterns
  - Cross-linguistic dialogue comparison

## Technical Debt
- [x] Remove deprecated MDSL auto-completion code completely
- [ ] Standardize error handling patterns across helpers
- [ ] Improve test coverage for configuration loading
- [ ] Fix inconsistent API key validation in ai_user_agent.rb
- [ ] Consider removing ENV-only variables that should use CONFIG

## Completed Technical Improvements
- [x] Implement Mistral image support for vision-capable models
  - Added multimodal message handling in mistral_helper.rb
  - Updated model_spec.js to mark Mistral Medium 2505 as vision-capable
  - Pixtral models already had vision_capability flag set

## Known Issues
- [ ] Browser Mode descriptions need cleanup in some documentation
- [ ] Some log paths might still reference ~/monadic/logs instead of ~/monadic/log
- [ ] Help database loading issues in packaged app (psycopg2 connection)
- [ ] Inconsistent file path handling between container and local development

---
*Last updated: 2025-01-18*