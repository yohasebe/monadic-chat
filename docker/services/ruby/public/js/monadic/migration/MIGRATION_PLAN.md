# State Migration Plan & Legacy Code Removal Strategy

## Overview
This document outlines the plan for migrating from scattered global variables to a centralized state management system, and the strategy for safely removing legacy code.

## Current Status (2025-01-08)

### ✅ Completed Components
1. **SessionState** - Central state object with event system
2. **MessageMigration** - Message array management
3. **SessionMigration** - Session lifecycle management
4. **AppStateMigration** - Application selection and parameters
5. **WebSocketMigration** - Connection and reconnection management
6. **UIStateMigration** - UI state and user preferences
7. **AudioStateMigration** - Audio playback and recording
8. **RollbackManager** - Safety mechanism with auto-rollback
9. **MigrationDashboard** - Real-time monitoring (Ctrl+Shift+M)
10. **EnvironmentDetector** - Environment-aware storage and paths

### 📊 Migration Statistics
- **Total Migration Files**: 10
- **Lines of Code**: ~4,500
- **Test Coverage**: Basic test structure in place
- **Safety Features**: Auto-rollback, feature flags, monitoring

## Legacy Variables to Migrate

### Priority 1 - Session & Messages (✅ DONE)
```javascript
// Old way
window.forceNewSession = true;
window.justReset = true;
messages = [];

// New way
SessionState.setResetFlags();
SessionState.clearMessages();
```

### Priority 2 - App State (✅ DONE)
```javascript
// Old way
window.loadedApp = 'chat';
window.params = { model: 'gpt-4' };

// New way
AppStateManager.setCurrentApp('chat', { model: 'gpt-4' });
```

### Priority 3 - WebSocket (✅ DONE)
```javascript
// Old way
window.ws = new WebSocket(url);

// New way
WebSocketManager.connect(url);
```

### Priority 4 - Audio (✅ DONE)
```javascript
// Old way
globalAudioQueue.push(audio);
isProcessingAudioQueue = true;

// New way
AudioStateManager.addToQueue(audio);
```

## Files Using Legacy Variables

### Core Files (Need Careful Migration)
1. `public/js/monadic.js` - Main application file
2. `public/js/monadic/websocket.js` - WebSocket handling
3. `public/js/monadic/utilities.js` - Utility functions
4. `public/js/monadic/tts.js` - Text-to-speech
5. `public/js/monadic/websocket-audio-improvements.js` - Audio improvements

### Patch Files (Special Handling)
1. `public/js/monadic/utilities_websearch_patch.js` - Overrides utilities.js functions

## Migration Phases

### Phase 1: Silent Parallel Running (CURRENT)
- ✅ All migrations disabled by default
- ✅ Legacy code continues to work
- ✅ Migrations can be enabled for testing
- ✅ Monitoring dashboard available

### Phase 2: Gradual Enablement
- Enable migrations one by one in development
- Monitor for issues using dashboard
- Fix any compatibility problems
- Test with different apps and providers

### Phase 3: Production Testing
- Enable for specific users/sessions
- A/B testing approach
- Collect metrics and feedback
- Fine-tune based on real usage

### Phase 4: Full Migration
- Enable by default for all users
- Keep legacy code as fallback
- Monitor error rates
- Ready for rollback if needed

### Phase 5: Legacy Removal
- Remove legacy variable declarations
- Remove old event handlers
- Clean up redundant code
- Maintain minimal backward compatibility layer

## Rollback Strategy

### Automatic Rollback
- Triggers on 5+ errors
- Disables all migrations
- Restores original functions
- Logs rollback event

### Manual Rollback
```javascript
// Browser console
rollback()

// Or click ROLLBACK button in dashboard
```

### Rollback Testing
```javascript
// Test rollback mechanism
RollbackManager.recordError(new Error('Test'), 'test');
// Repeat 5 times to trigger auto-rollback
```

## Testing Strategy

### Unit Tests
```bash
npm test -- test/frontend/migration/
```

### Integration Tests
```bash
rake spec_e2e
```

### Manual Testing Checklist
- [ ] Test with each app type
- [ ] Test with different providers
- [ ] Test WebSocket reconnection
- [ ] Test audio playback
- [ ] Test file uploads
- [ ] Test session persistence
- [ ] Test rollback mechanism

## Migration Commands

### Development Testing
```javascript
// Enable all migrations
enableMigrations()

// Test all components
testMigrations()

// Show monitoring dashboard
migrationDashboard() // or Ctrl+Shift+M

// Disable all migrations
disableMigrations()
```

### Production Deployment
```javascript
// Enable specific feature
MigrationConfig.features.messages = true;

// Check consistency
MigrationConfig.checkConsistency();

// Get status
MigrationConfig.getStatus();
```

## Risk Assessment

### Low Risk Components
- SessionState (foundation layer)
- MessageMigration (simple array management)
- RollbackManager (safety mechanism)

### Medium Risk Components
- AppStateMigration (affects app switching)
- UIStateMigration (affects user interaction)
- AudioStateMigration (affects playback)

### High Risk Components
- WebSocketMigration (critical for communication)
- Session persistence (data loss potential)

## Success Metrics

### Technical Metrics
- Error rate < 0.1%
- Rollback rate < 1%
- Performance impact < 5ms
- Memory usage stable

### User Metrics
- No increase in bug reports
- No degradation in user experience
- Successful A/B test results

## Timeline

### Week 1-2 (DONE)
- ✅ Implement all migration components
- ✅ Add rollback mechanism
- ✅ Create monitoring dashboard

### Week 3-4 (CURRENT)
- 🔄 Test in development environment
- 📝 Document migration process
- 🧪 Write comprehensive tests

### Week 5-6
- Enable gradually in production
- Monitor and fix issues
- Gather feedback

### Week 7-8
- Full rollout
- Legacy code removal
- Performance optimization

## Maintenance Plan

### Monitoring
- Check dashboard daily during rollout
- Review error logs
- Track performance metrics

### Updates
- Fix issues within 24 hours
- Document all changes
- Update tests

### Communication
- Notify team of changes
- Document in CLAUDE.md
- Update user documentation if needed

## Conclusion

The migration system is designed to be:
1. **Safe** - Multiple safety mechanisms
2. **Gradual** - No big-bang migration
3. **Reversible** - Can rollback anytime
4. **Observable** - Real-time monitoring
5. **Tested** - Comprehensive test coverage

The key to success is patience and careful monitoring during each phase.

## Contact

For questions or issues related to the migration:
- Check the monitoring dashboard (Ctrl+Shift+M)
- Review browser console for errors
- Check CLAUDE.md for latest updates
- Run `testMigrations()` for diagnostics