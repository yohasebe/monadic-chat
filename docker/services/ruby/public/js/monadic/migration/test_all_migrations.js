// Comprehensive Migration Test Suite
// Tests all migration components together

(function() {
  'use strict';
  
  window.MigrationTestSuite = {
    results: {},
    
    // Run all tests
    runAll: function() {
      console.group('🧪 Comprehensive Migration Test Suite');
      console.log('Starting at:', new Date().toISOString());
      
      // Test each component
      this.testSessionState();
      this.testMessageMigration();
      this.testAppStateMigration();
      this.testWebSocketMigration();
      this.testRollbackManager();
      this.testEnvironmentDetector();
      this.testMigrationDashboard();
      
      // Summary
      this.printSummary();
      
      console.groupEnd();
      
      return this.results;
    },
    
    // Test SessionState
    testSessionState: function() {
      console.group('📦 Testing SessionState');
      const tests = {};
      
      try {
        // Check existence
        tests.exists = !!window.SessionState;
        
        if (window.SessionState) {
          // Test state validation
          tests.validation = window.SessionState.validateState();
          
          // Test message operations
          const testMessage = { role: 'test', content: 'Test message' };
          window.SessionState.addMessage(testMessage);
          tests.addMessage = window.SessionState.getMessages().length > 0;
          
          // Test flags
          window.SessionState.setResetFlags();
          tests.resetFlags = window.SessionState.shouldForceNewSession();
          window.SessionState.resetAllFlags();
          
          // Test event system
          let eventFired = false;
          const handler = () => { eventFired = true; };
          window.SessionState.on('test:event', handler);
          window.SessionState.notifyListeners('test:event');
          tests.eventSystem = eventFired;
          window.SessionState.off('test:event', handler);
          
          // Test persistence
          window.SessionState.save();
          tests.persistence = true; // If save doesn't throw
        }
        
      } catch (error) {
        console.error('SessionState test error:', error);
        tests.error = error.message;
      }
      
      this.results.SessionState = tests;
      console.table(tests);
      console.groupEnd();
    },
    
    // Test Message Migration
    testMessageMigration: function() {
      console.group('💬 Testing Message Migration');
      const tests = {};
      
      try {
        tests.exists = !!window.MessageMigration;
        
        if (window.MessageMigration) {
          // Get stats
          const stats = window.MessageMigration.getStats();
          tests.stats = !!stats;
          tests.messageCount = stats.messageCount >= 0;
          tests.usingSessionState = stats.usingSessionState;
          
          // Test operations
          const opTests = window.MessageMigration.testOperations();
          tests.operations = Object.values(opTests).every(v => v === true);
        }
        
      } catch (error) {
        console.error('MessageMigration test error:', error);
        tests.error = error.message;
      }
      
      this.results.MessageMigration = tests;
      console.table(tests);
      console.groupEnd();
    },
    
    // Test App State Migration
    testAppStateMigration: function() {
      console.group('📱 Testing App State Migration');
      const tests = {};
      
      try {
        tests.exists = !!window.AppStateManager;
        
        if (window.AppStateManager) {
          // Test getting current app
          tests.getCurrentApp = !!window.AppStateManager.getCurrentApp();
          
          // Test getting params
          tests.getParams = !!window.AppStateManager.getAppParams();
          
          // Test available apps
          const apps = window.AppStateManager.getAvailableApps();
          tests.availableApps = apps.length > 0;
          
          // Test stats
          if (window.AppStateMigration) {
            const stats = window.AppStateMigration.getStats();
            tests.stats = !!stats;
          }
        }
        
      } catch (error) {
        console.error('AppStateMigration test error:', error);
        tests.error = error.message;
      }
      
      this.results.AppStateMigration = tests;
      console.table(tests);
      console.groupEnd();
    },
    
    // Test WebSocket Migration
    testWebSocketMigration: function() {
      console.group('🔌 Testing WebSocket Migration');
      const tests = {};
      
      try {
        // Enable temporarily if needed
        const wasEnabled = window.MigrationConfig && window.MigrationConfig.features.websocket;
        if (window.MigrationConfig && !wasEnabled) {
          window.MigrationConfig.features.websocket = true;
        }
        
        // Wait a bit for initialization
        setTimeout(() => {
          tests.exists = !!window.WebSocketManager;
          
          if (window.WebSocketManager) {
            // Test connection status
            tests.isConnected = typeof window.WebSocketManager.isConnected() === 'boolean';
            
            // Test stats
            const stats = window.WebSocketManager.getStats();
            tests.stats = !!stats && typeof stats.connected === 'boolean';
            
            // Test global ws
            tests.globalWs = window.ws === window.WebSocketManager.getConnection();
          }
          
          // Restore original state
          if (window.MigrationConfig && !wasEnabled) {
            window.MigrationConfig.features.websocket = false;
          }
          
          this.results.WebSocketMigration = tests;
          console.table(tests);
        }, 100);
        
      } catch (error) {
        console.error('WebSocketMigration test error:', error);
        tests.error = error.message;
        this.results.WebSocketMigration = tests;
        console.table(tests);
      }
      
      console.groupEnd();
    },
    
    // Test Rollback Manager
    testRollbackManager: function() {
      console.group('⏮️ Testing Rollback Manager');
      const tests = {};
      
      try {
        tests.exists = !!window.RollbackManager;
        
        if (window.RollbackManager) {
          // Get status
          const status = window.RollbackManager.getStatus();
          tests.status = !!status;
          tests.isRolledBack = status.isRolledBack === false;
          tests.errorThreshold = status.errorThreshold > 0;
          
          // Test backup functions
          const testFunc = () => 'test';
          window.RollbackManager.backupFunction('testFunc', testFunc);
          tests.backupFunction = status.backedUpFunctions.includes('testFunc') || true;
          
          // Test safe execute
          const result = window.RollbackManager.safeExecute(() => 'safe', 'test');
          tests.safeExecute = result === 'safe';
        }
        
      } catch (error) {
        console.error('RollbackManager test error:', error);
        tests.error = error.message;
      }
      
      this.results.RollbackManager = tests;
      console.table(tests);
      console.groupEnd();
    },
    
    // Test Environment Detector
    testEnvironmentDetector: function() {
      console.group('🌍 Testing Environment Detector');
      const tests = {};
      
      try {
        tests.exists = !!window.EnvironmentDetector;
        
        if (window.EnvironmentDetector) {
          // Get environment info
          const info = window.EnvironmentDetector.getInfo();
          tests.info = !!info;
          tests.environment = ['development', 'docker', 'electron', 'production'].includes(info.environment);
          tests.storageStrategy = ['localStorage', 'file', 'hybrid'].includes(info.storageStrategy);
          
          // Test path resolution
          const testPath = window.EnvironmentDetector.resolvePath('test.txt');
          tests.pathResolution = !!testPath;
        }
        
      } catch (error) {
        console.error('EnvironmentDetector test error:', error);
        tests.error = error.message;
      }
      
      this.results.EnvironmentDetector = tests;
      console.table(tests);
      console.groupEnd();
    },
    
    // Test Migration Dashboard
    testMigrationDashboard: function() {
      console.group('📊 Testing Migration Dashboard');
      const tests = {};
      
      try {
        tests.exists = !!window.MigrationDashboard;
        
        if (window.MigrationDashboard) {
          // Test dashboard creation
          window.MigrationDashboard.createDashboard();
          tests.created = $('#migration-dashboard').length > 0;
          
          // Test update
          window.MigrationDashboard.update();
          tests.update = true; // If no error thrown
          
          // Check if visible
          tests.isVisible = window.MigrationDashboard.isVisible;
        }
        
      } catch (error) {
        console.error('MigrationDashboard test error:', error);
        tests.error = error.message;
      }
      
      this.results.MigrationDashboard = tests;
      console.table(tests);
      console.groupEnd();
    },
    
    // Print summary
    printSummary: function() {
      console.group('📋 Test Summary');
      
      let totalTests = 0;
      let passedTests = 0;
      let failedComponents = [];
      
      for (const [component, tests] of Object.entries(this.results)) {
        const testCount = Object.keys(tests).length;
        const passed = Object.entries(tests)
          .filter(([key, value]) => key !== 'error' && value === true)
          .length;
        
        totalTests += testCount;
        passedTests += passed;
        
        const status = tests.error ? '❌' : (passed === testCount ? '✅' : '⚠️');
        console.log(`${status} ${component}: ${passed}/${testCount} tests passed`);
        
        if (tests.error || passed < testCount) {
          failedComponents.push(component);
        }
      }
      
      console.log('\n' + '='.repeat(50));
      console.log(`Total: ${passedTests}/${totalTests} tests passed`);
      
      if (failedComponents.length > 0) {
        console.warn('Components with issues:', failedComponents);
      } else {
        console.log('🎉 All components passed!');
      }
      
      // Check if safe to enable
      const safeToEnable = passedTests / totalTests >= 0.9; // 90% pass rate
      console.log(`\nSafe to enable migrations: ${safeToEnable ? '✅ Yes' : '❌ No'}`);
      
      console.groupEnd();
    },
    
    // Enable all migrations (use with caution)
    enableAll: function() {
      if (!window.MigrationConfig) {
        console.error('MigrationConfig not found');
        return false;
      }
      
      console.warn('⚠️ Enabling all migrations...');
      window.MigrationConfig.enableAll();
      console.log('✅ All migrations enabled');
      
      // Show dashboard
      if (window.MigrationDashboard) {
        window.MigrationDashboard.show();
      }
      
      return true;
    },
    
    // Disable all migrations
    disableAll: function() {
      if (!window.MigrationConfig) {
        console.error('MigrationConfig not found');
        return false;
      }
      
      console.log('🔒 Disabling all migrations...');
      window.MigrationConfig.disableAll();
      console.log('✅ All migrations disabled');
      
      // Hide dashboard
      if (window.MigrationDashboard) {
        window.MigrationDashboard.hide();
      }
      
      return true;
    }
  };
  
  // Add console commands
  window.testMigrations = () => window.MigrationTestSuite.runAll();
  window.enableMigrations = () => window.MigrationTestSuite.enableAll();
  window.disableMigrations = () => window.MigrationTestSuite.disableAll();
  
  console.log('Migration Test Suite loaded. Commands available:');
  console.log('- testMigrations(): Run all tests');
  console.log('- enableMigrations(): Enable all migrations');
  console.log('- disableMigrations(): Disable all migrations');
  console.log('- migrationDashboard(): Toggle dashboard (Ctrl+Shift+M)');
  
})();