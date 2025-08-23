# Language Setting Awareness by App

## Apps that USE the language selector setting

These apps will respect the user's language preference from the language selector:

### Standard Chat Apps
- Chat (all providers)
- Chat Plus (all providers)
- Coding Assistant
- Content Reader
- Research Assistant
- Second Opinion
- Math Tutor
- Mail Composer
- Novel Writer
- Speech Draft Helper
- Monadic Help
- PDF Navigator

### Creative Apps
- Image Generator
- Video Generator
- DrawIO Grapher
- Concept Visualizer
- Syntax Tree

### Code-related Apps
- Code Interpreter
- Jupyter Notebook

## Apps with PARTIAL language selector support

These apps respect the language selector for initial interactions but have their own language management for core functionality:

### Translation & Language Learning Apps
- **Voice Interpreter** - Uses user's language for initial question, then manages translation languages
- **Translate** - Uses user's language to ask for source/target languages
- **Language Practice** - Uses user's language for initial greeting and questions about learning goals
- **Language Practice Plus** - Similar to Language Practice with enhanced features

### How these apps use the language setting

These apps are specifically designed for language learning and translation:
1. **Initial interactions** - Use the user's preferred language for greetings and setup questions
2. **Core functionality** - Manage languages independently as part of their primary purpose
3. **Explanations** - Fall back to user's preferred language when providing help or clarification
4. **Multiple languages** - Support simultaneous use of different languages for learning/translation

## Recommendations

For translation and language learning apps:
- Apps now use the language selector for initial interactions (improved UX)
- Core functionality still manages languages independently (as needed)
- This hybrid approach provides better user experience while maintaining functionality

For other apps:
- All standard conversation apps correctly use the language selector
- The language preference is properly injected into system prompts
- RTL languages are handled appropriately in the UI