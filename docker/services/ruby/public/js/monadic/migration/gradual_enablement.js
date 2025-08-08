// Gradual Enablement Strategy
// Controls phased rollout of migration features

(function() {
  'use strict';
  
  window.GradualEnablement = {
    // Rollout phases
    phases: {
      testing: {
        name: 'Testing',
        features: [],
        percentage: 0
      },
      alpha: {
        name: 'Alpha',
        features: ['messages', 'session'],
        percentage: 1
      },
      beta: {
        name: 'Beta',
        features: ['messages', 'session', 'app', 'ui'],
        percentage: 10
      },
      staged: {
        name: 'Staged Rollout',
        features: ['messages', 'session', 'app', 'ui', 'websocket'],
        percentage: 50
      },
      production: {
        name: 'Production',
        features: ['messages', 'session', 'app', 'ui', 'websocket', 'audio'],
        percentage: 100
      }
    },
    
    // Current phase
    currentPhase: 'testing',
    
    // User eligibility cache
    eligibilityCache: new Map(),
    
    // Feature override for specific users
    userOverrides: new Map(),
    
    // Initialize gradual enablement
    init: function() {
      console.log('[GradualEnablement] Initializing');
      
      // Load saved phase
      this.loadPhase();
      
      // Check user eligibility
      this.checkEligibility();
      
      // Apply phase settings
      this.applyPhase();
      
      // Set up monitoring
      this.setupMonitoring();
      
      return this;
    },
    
    // Load saved phase from storage
    loadPhase: function() {
      try {
        const saved = localStorage.getItem('migrationPhase');
        if (saved && this.phases[saved]) {
          this.currentPhase = saved;
        }
        
        // Check for phase override in URL
        const urlParams = new URLSearchParams(window.location.search);
        const phaseParam = urlParams.get('migration_phase');
        if (phaseParam && this.phases[phaseParam]) {
          console.log(`[GradualEnablement] Phase override from URL: ${phaseParam}`);
          this.currentPhase = phaseParam;
        }
        
      } catch (error) {
        console.error('[GradualEnablement] Failed to load phase:', error);
      }
    },
    
    // Check if current user is eligible for migration
    checkEligibility: function() {
      const userId = this.getUserId();
      
      // Check cache first
      if (this.eligibilityCache.has(userId)) {
        return this.eligibilityCache.get(userId);
      }
      
      // Check user override
      if (this.userOverrides.has(userId)) {
        const eligible = this.userOverrides.get(userId);
        this.eligibilityCache.set(userId, eligible);
        return eligible;
      }
      
      // Check percentage rollout
      const phase = this.phases[this.currentPhase];
      const eligible = this.isInPercentage(userId, phase.percentage);
      
      this.eligibilityCache.set(userId, eligible);
      return eligible;
    },
    
    // Get or generate user ID
    getUserId: function() {
      let userId = localStorage.getItem('userId');
      
      if (!userId) {
        // Generate new user ID
        userId = 'user_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
        localStorage.setItem('userId', userId);
      }
      
      return userId;
    },
    
    // Check if user is in percentage rollout
    isInPercentage: function(userId, percentage) {
      if (percentage === 0) return false;
      if (percentage === 100) return true;
      
      // Use consistent hash to determine eligibility
      const hash = this.hashCode(userId);
      const bucket = Math.abs(hash) % 100;
      
      return bucket < percentage;
    },
    
    // Simple hash function
    hashCode: function(str) {
      let hash = 0;
      for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Convert to 32-bit integer
      }
      return hash;
    },
    
    // Apply current phase settings
    applyPhase: function() {
      if (!window.MigrationConfig) {
        console.warn('[GradualEnablement] MigrationConfig not found');
        return;
      }
      
      const phase = this.phases[this.currentPhase];
      const eligible = this.checkEligibility();
      
      console.log(`[GradualEnablement] Phase: ${phase.name}, Eligible: ${eligible}`);
      
      if (eligible) {
        // Enable features for this phase
        phase.features.forEach(feature => {
          window.MigrationConfig.features[feature] = true;
        });
        
        console.log('[GradualEnablement] Enabled features:', phase.features);
      } else {
        // Ensure all features are disabled
        window.MigrationConfig.disableAll();
        console.log('[GradualEnablement] User not eligible, features disabled');
      }
      
      // Notify dashboard
      if (window.MigrationDashboard) {
        setTimeout(() => {
          window.MigrationDashboard.update();
        }, 1000);
      }
    },
    
    // Change phase
    setPhase: function(phaseName) {
      if (!this.phases[phaseName]) {
        console.error(`[GradualEnablement] Unknown phase: ${phaseName}`);
        return false;
      }
      
      console.log(`[GradualEnablement] Changing phase from ${this.currentPhase} to ${phaseName}`);
      
      this.currentPhase = phaseName;
      localStorage.setItem('migrationPhase', phaseName);
      
      // Clear eligibility cache
      this.eligibilityCache.clear();
      
      // Reapply settings
      this.applyPhase();
      
      return true;
    },
    
    // Add user override
    addUserOverride: function(userId, eligible) {
      this.userOverrides.set(userId, eligible);
      this.eligibilityCache.delete(userId);
      
      console.log(`[GradualEnablement] User override added: ${userId} = ${eligible}`);
      
      // Recheck if it's the current user
      if (userId === this.getUserId()) {
        this.applyPhase();
      }
    },
    
    // Get rollout statistics
    getStats: function() {
      const phase = this.phases[this.currentPhase];
      const userId = this.getUserId();
      const eligible = this.checkEligibility();
      
      return {
        currentPhase: this.currentPhase,
        phaseName: phase.name,
        features: phase.features,
        percentage: phase.percentage,
        userId: userId,
        eligible: eligible,
        hasOverride: this.userOverrides.has(userId)
      };
    },
    
    // Setup monitoring
    setupMonitoring: function() {
      // Track migration success/failure
      if (window.SessionState) {
        window.SessionState.on('migration:error', (error) => {
          this.recordError(error);
        });
        
        window.SessionState.on('migration:success', () => {
          this.recordSuccess();
        });
      }
      
      // Check health periodically
      setInterval(() => {
        this.checkHealth();
      }, 60000); // Every minute
    },
    
    // Record migration error
    recordError: function(error) {
      const stats = this.getErrorStats();
      stats.count++;
      stats.lastError = Date.now();
      stats.errors.push({
        time: Date.now(),
        phase: this.currentPhase,
        error: error.message || error
      });
      
      // Keep only last 100 errors
      if (stats.errors.length > 100) {
        stats.errors.shift();
      }
      
      this.saveErrorStats(stats);
      
      // Check if we should auto-disable
      if (stats.count > 10 && (Date.now() - stats.firstError) < 300000) { // 10 errors in 5 minutes
        console.warn('[GradualEnablement] Too many errors, disabling migrations');
        this.emergencyDisable();
      }
    },
    
    // Record migration success
    recordSuccess: function() {
      const stats = this.getSuccessStats();
      stats.count++;
      stats.lastSuccess = Date.now();
      
      this.saveSuccessStats(stats);
    },
    
    // Get error statistics
    getErrorStats: function() {
      try {
        const saved = localStorage.getItem('migrationErrorStats');
        return saved ? JSON.parse(saved) : {
          count: 0,
          firstError: Date.now(),
          lastError: null,
          errors: []
        };
      } catch {
        return { count: 0, firstError: Date.now(), lastError: null, errors: [] };
      }
    },
    
    // Save error statistics
    saveErrorStats: function(stats) {
      try {
        localStorage.setItem('migrationErrorStats', JSON.stringify(stats));
      } catch (error) {
        console.error('[GradualEnablement] Failed to save error stats:', error);
      }
    },
    
    // Get success statistics
    getSuccessStats: function() {
      try {
        const saved = localStorage.getItem('migrationSuccessStats');
        return saved ? JSON.parse(saved) : {
          count: 0,
          firstSuccess: null,
          lastSuccess: null
        };
      } catch {
        return { count: 0, firstSuccess: null, lastSuccess: null };
      }
    },
    
    // Save success statistics
    saveSuccessStats: function(stats) {
      try {
        localStorage.setItem('migrationSuccessStats', JSON.stringify(stats));
      } catch (error) {
        console.error('[GradualEnablement] Failed to save success stats:', error);
      }
    },
    
    // Check system health
    checkHealth: function() {
      const errorStats = this.getErrorStats();
      const successStats = this.getSuccessStats();
      
      // Calculate error rate
      const total = errorStats.count + successStats.count;
      const errorRate = total > 0 ? (errorStats.count / total) * 100 : 0;
      
      console.log(`[GradualEnablement] Health check - Error rate: ${errorRate.toFixed(2)}%, Total: ${total}`);
      
      // Alert if error rate is high
      if (errorRate > 10 && total > 10) {
        console.warn('[GradualEnablement] High error rate detected');
        
        // Consider rolling back to previous phase
        if (this.currentPhase !== 'testing') {
          this.considerRollback();
        }
      }
    },
    
    // Consider rolling back to previous phase
    considerRollback: function() {
      const phases = Object.keys(this.phases);
      const currentIndex = phases.indexOf(this.currentPhase);
      
      if (currentIndex > 0) {
        const previousPhase = phases[currentIndex - 1];
        console.warn(`[GradualEnablement] Considering rollback to ${previousPhase}`);
        
        // Show confirmation to user if possible
        if (window.UIStateManager) {
          window.UIStateManager.showAlert(
            'Migration issues detected. Consider switching to a more stable phase.',
            'warning',
            10000
          );
        }
      }
    },
    
    // Emergency disable all migrations
    emergencyDisable: function() {
      console.error('[GradualEnablement] EMERGENCY DISABLE TRIGGERED');
      
      // Set phase to testing (no features)
      this.setPhase('testing');
      
      // Force disable all features
      if (window.MigrationConfig) {
        window.MigrationConfig.disableAll();
      }
      
      // Trigger rollback if available
      if (window.RollbackManager) {
        window.RollbackManager.manualRollback();
      }
      
      // Alert user
      if (window.UIStateManager) {
        window.UIStateManager.showAlert(
          'Migrations have been disabled due to errors. Please refresh the page.',
          'error',
          0
        );
      }
    },
    
    // Reset all statistics
    resetStats: function() {
      localStorage.removeItem('migrationErrorStats');
      localStorage.removeItem('migrationSuccessStats');
      this.eligibilityCache.clear();
      
      console.log('[GradualEnablement] Statistics reset');
    },
    
    // Get complete status
    getStatus: function() {
      return {
        ...this.getStats(),
        errorStats: this.getErrorStats(),
        successStats: this.getSuccessStats(),
        phases: Object.keys(this.phases).map(key => ({
          key: key,
          ...this.phases[key],
          active: key === this.currentPhase
        }))
      };
    }
  };
  
  // Initialize on load
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    window.GradualEnablement.init();
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      window.GradualEnablement.init();
    });
  }
  
  // Console commands
  window.setMigrationPhase = (phase) => window.GradualEnablement.setPhase(phase);
  window.getMigrationStatus = () => window.GradualEnablement.getStatus();
  window.resetMigrationStats = () => window.GradualEnablement.resetStats();
  
  console.log('[GradualEnablement] Commands available:');
  console.log('- setMigrationPhase(phase): Set migration phase (testing/alpha/beta/staged/production)');
  console.log('- getMigrationStatus(): Get current migration status');
  console.log('- resetMigrationStats(): Reset error and success statistics');
  
})();