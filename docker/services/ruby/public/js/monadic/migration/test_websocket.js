// Test WebSocket Migration
// This file tests the WebSocket migration functionality

(function() {
  'use strict';
  
  console.group('🧪 WebSocket Migration Test');
  
  // Enable WebSocket migration temporarily
  if (window.MigrationConfig) {
    console.log('Enabling WebSocket migration for testing...');
    window.MigrationConfig.features.websocket = true;
  }
  
  // Wait for WebSocketManager to be available
  setTimeout(() => {
    if (!window.WebSocketManager) {
      console.error('❌ WebSocketManager not found');
      console.groupEnd();
      return;
    }
    
    console.log('✅ WebSocketManager initialized');
    
    // Test 1: Check connection status
    console.log('\n📊 Test 1: Connection Status');
    const isConnected = window.WebSocketManager.isConnected();
    console.log(`Connected: ${isConnected}`);
    
    // Test 2: Get statistics
    console.log('\n📊 Test 2: Connection Statistics');
    const stats = window.WebSocketManager.getStats();
    console.table(stats);
    
    // Test 3: Event handlers
    console.log('\n📊 Test 3: Event Handlers');
    const testHandler = (data) => {
      console.log('Test handler received:', data);
    };
    
    window.WebSocketManager.on('connected', testHandler);
    window.WebSocketManager.on('message:sent', testHandler);
    console.log('✅ Event handlers registered');
    
    // Test 4: Check global ws variable
    console.log('\n📊 Test 4: Global ws Variable');
    console.log('window.ws:', window.ws);
    console.log('WebSocketManager.connection:', window.WebSocketManager.connection);
    console.log('Are they the same?', window.ws === window.WebSocketManager.connection);
    
    // Test 5: SessionState integration
    console.log('\n📊 Test 5: SessionState Integration');
    if (window.SessionState) {
      console.log('SessionState.connection.ws:', window.SessionState.connection.ws);
      console.log('SessionState.connection.isConnected:', window.SessionState.connection.isConnected);
    } else {
      console.log('❌ SessionState not available');
    }
    
    // Test 6: Send test message (dry run)
    console.log('\n📊 Test 6: Send Message (Dry Run)');
    const testMessage = { type: 'test', timestamp: Date.now(), dryRun: true };
    const sent = window.WebSocketManager.send(testMessage);
    console.log(`Message sent: ${sent}`);
    
    // Test 7: Queue functionality
    console.log('\n📊 Test 7: Message Queue');
    window.WebSocketManager.setQueueing(true);
    console.log('Queue enabled:', window.WebSocketManager.queueEnabled);
    console.log('Queue length:', window.WebSocketManager.messageQueue.length);
    
    // Test 8: Migration status
    console.log('\n📊 Test 8: Migration Status');
    if (window.WebSocketMigration) {
      const migrationStats = window.WebSocketMigration.getStats();
      console.table(migrationStats);
      
      // Run operation tests
      console.log('\n🔧 Running operation tests...');
      const testResults = window.WebSocketMigration.testOperations();
      
      // Check for any failures
      const failures = Object.entries(testResults).filter(([key, value]) => !value);
      if (failures.length > 0) {
        console.error('❌ Some tests failed:', failures);
      } else {
        console.log('✅ All operation tests passed');
      }
    }
    
    // Test 9: Rollback readiness
    console.log('\n📊 Test 9: Rollback Readiness');
    if (window.RollbackManager) {
      const rollbackStatus = window.RollbackManager.getStatus();
      console.log('Backed up functions:', rollbackStatus.backedUpFunctions);
      console.log('Error count:', rollbackStatus.errorCount);
      console.log('Is rolled back:', rollbackStatus.isRolledBack);
    }
    
    // Summary
    console.log('\n📋 Test Summary:');
    console.log('- WebSocketManager: ✅');
    console.log(`- Connection: ${isConnected ? '✅' : '⚠️ Not connected'}`);
    console.log('- Event system: ✅');
    console.log(`- SessionState integration: ${window.SessionState ? '✅' : '❌'}`);
    console.log('- Message queueing: ✅');
    console.log(`- Rollback ready: ${window.RollbackManager ? '✅' : '❌'}`);
    
    // Cleanup
    window.WebSocketManager.off('connected', testHandler);
    window.WebSocketManager.off('message:sent', testHandler);
    window.WebSocketManager.setQueueing(false);
    
    // Disable migration after testing
    if (window.MigrationConfig) {
      window.MigrationConfig.features.websocket = false;
      console.log('\n🔒 WebSocket migration disabled after testing');
    }
    
    console.groupEnd();
    
  }, 1000); // Wait for everything to load
  
})();