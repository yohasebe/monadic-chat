// Migration Dashboard
// Real-time monitoring of state migration progress and health

(function() {
  'use strict';
  
  window.MigrationDashboard = {
    // Dashboard state
    isVisible: false,
    updateInterval: null,
    updateFrequency: 2000, // Update every 2 seconds
    
    // Create dashboard HTML
    createDashboard: function() {
      if ($('#migration-dashboard').length) {
        return; // Already exists
      }
      
      const dashboardHTML = `
        <div id="migration-dashboard" style="
          position: fixed;
          top: 10px;
          right: 10px;
          width: 350px;
          max-height: 80vh;
          background: rgba(0, 0, 0, 0.9);
          color: #0f0;
          font-family: 'Courier New', monospace;
          font-size: 11px;
          border: 1px solid #0f0;
          border-radius: 5px;
          padding: 10px;
          z-index: 10000;
          overflow-y: auto;
          display: none;
        ">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
            <h3 style="margin: 0; color: #0f0;">Migration Dashboard</h3>
            <button id="migration-dashboard-close" style="
              background: transparent;
              border: 1px solid #0f0;
              color: #0f0;
              cursor: pointer;
              padding: 2px 8px;
            ">✕</button>
          </div>
          
          <div id="migration-environment" class="dashboard-section">
            <h4 style="color: #0f0; margin: 5px 0;">Environment</h4>
            <div class="dashboard-content"></div>
          </div>
          
          <div id="migration-status" class="dashboard-section">
            <h4 style="color: #0f0; margin: 5px 0;">Migration Status</h4>
            <div class="dashboard-content"></div>
          </div>
          
          <div id="migration-features" class="dashboard-section">
            <h4 style="color: #0f0; margin: 5px 0;">Features</h4>
            <div class="dashboard-content"></div>
          </div>
          
          <div id="migration-health" class="dashboard-section">
            <h4 style="color: #0f0; margin: 5px 0;">Health Check</h4>
            <div class="dashboard-content"></div>
          </div>
          
          <div id="migration-stats" class="dashboard-section">
            <h4 style="color: #0f0; margin: 5px 0;">Statistics</h4>
            <div class="dashboard-content"></div>
          </div>
          
          <div id="migration-errors" class="dashboard-section">
            <h4 style="color: #0f0; margin: 5px 0;">Recent Errors</h4>
            <div class="dashboard-content"></div>
          </div>
          
          <div id="migration-controls" class="dashboard-section" style="margin-top: 10px; padding-top: 10px; border-top: 1px solid #0f0;">
            <button class="dashboard-btn" onclick="MigrationDashboard.toggleAutoUpdate()">Toggle Auto-Update</button>
            <button class="dashboard-btn" onclick="MigrationDashboard.refresh()">Refresh</button>
            <button class="dashboard-btn" onclick="MigrationConfig.showDashboard()">Console Log</button>
            <button class="dashboard-btn" style="background: #f00; color: #fff;" onclick="RollbackManager.manualRollback()">ROLLBACK</button>
          </div>
        </div>
      `;
      
      $('body').append(dashboardHTML);
      
      // Add styles
      const styles = `
        <style>
          .dashboard-section {
            margin-bottom: 10px;
            padding: 5px;
            border: 1px solid #0f0;
            border-radius: 3px;
          }
          .dashboard-content {
            padding: 5px;
            font-size: 10px;
            line-height: 1.4;
          }
          .dashboard-btn {
            background: #0f0;
            color: #000;
            border: none;
            padding: 5px 10px;
            margin: 2px;
            cursor: pointer;
            font-size: 10px;
            border-radius: 3px;
          }
          .dashboard-btn:hover {
            background: #0a0;
          }
          .status-enabled { color: #0f0; }
          .status-disabled { color: #f00; }
          .status-warning { color: #ff0; }
        </style>
      `;
      
      if (!$('#migration-dashboard-styles').length) {
        $('head').append(`<div id="migration-dashboard-styles">${styles}</div>`);
      }
      
      // Add event handlers
      $('#migration-dashboard-close').on('click', () => this.hide());
    },
    
    // Update dashboard content
    update: function() {
      if (!this.isVisible) return;
      
      // Update environment
      if (window.EnvironmentDetector) {
        const env = window.EnvironmentDetector.getInfo();
        $('#migration-environment .dashboard-content').html(`
          <div>Environment: <span class="status-enabled">${env.environment}</span></div>
          <div>Storage: ${env.storageStrategy}</div>
          <div>Host: ${env.hostname}:${env.port || 'default'}</div>
        `);
      }
      
      // Update migration status
      if (window.MigrationConfig) {
        const enabled = window.MigrationConfig.enabled;
        $('#migration-status .dashboard-content').html(`
          <div>Master Switch: <span class="${enabled ? 'status-enabled' : 'status-disabled'}">${enabled ? 'ENABLED' : 'DISABLED'}</span></div>
          <div>Auto-Update: <span class="${this.updateInterval ? 'status-enabled' : 'status-disabled'}">${this.updateInterval ? 'ON' : 'OFF'}</span></div>
        `);
      }
      
      // Update features
      if (window.MigrationConfig) {
        const features = window.MigrationConfig.features;
        let featuresHTML = '';
        for (const [key, value] of Object.entries(features)) {
          featuresHTML += `<div>${key}: <span class="${value ? 'status-enabled' : 'status-disabled'}">${value ? '✓' : '✗'}</span></div>`;
        }
        $('#migration-features .dashboard-content').html(featuresHTML);
      }
      
      // Update health check
      this.updateHealthCheck();
      
      // Update statistics
      this.updateStatistics();
      
      // Update errors
      if (window.RollbackManager) {
        const status = window.RollbackManager.getStatus();
        let errorsHTML = `<div>Error Count: ${status.errorCount}/${status.errorThreshold}</div>`;
        
        if (status.recentErrors && status.recentErrors.length > 0) {
          errorsHTML += '<div style="margin-top: 5px;">Recent:</div>';
          status.recentErrors.forEach(error => {
            const time = new Date(error.timestamp).toLocaleTimeString();
            errorsHTML += `<div style="color: #f00; font-size: 9px;">[${time}] ${error.message || 'Unknown error'}</div>`;
          });
        } else {
          errorsHTML += '<div style="color: #0f0;">No errors</div>';
        }
        
        $('#migration-errors .dashboard-content').html(errorsHTML);
      }
    },
    
    // Update health check section
    updateHealthCheck: function() {
      let healthHTML = '';
      let allHealthy = true;
      
      // Check SessionState
      if (window.SessionState) {
        const valid = window.SessionState.validateState();
        healthHTML += `<div>SessionState: <span class="${valid ? 'status-enabled' : 'status-disabled'}">${valid ? 'Valid' : 'Invalid'}</span></div>`;
        if (!valid) allHealthy = false;
      }
      
      // Check consistency
      if (window.MigrationConfig) {
        const consistency = window.MigrationConfig.checkConsistency();
        healthHTML += `<div>Consistency: <span class="${consistency.consistent ? 'status-enabled' : 'status-disabled'}">${consistency.consistent ? 'OK' : 'Issues'}</span></div>`;
        if (!consistency.consistent) allHealthy = false;
      }
      
      // Check rollback status
      if (window.RollbackManager) {
        const status = window.RollbackManager.getStatus();
        healthHTML += `<div>Rollback: <span class="${status.isRolledBack ? 'status-warning' : 'status-enabled'}">${status.isRolledBack ? 'ROLLED BACK' : 'Ready'}</span></div>`;
        if (status.isRolledBack) allHealthy = false;
      }
      
      // Overall health
      healthHTML = `<div style="font-weight: bold;">Overall: <span class="${allHealthy ? 'status-enabled' : 'status-warning'}">${allHealthy ? 'HEALTHY' : 'ISSUES DETECTED'}</span></div>` + healthHTML;
      
      $('#migration-health .dashboard-content').html(healthHTML);
    },
    
    // Update statistics section
    updateStatistics: function() {
      let statsHTML = '';
      
      // Message stats
      if (window.MessageMigration) {
        const stats = window.MessageMigration.getStats();
        statsHTML += `<div><b>Messages:</b></div>`;
        statsHTML += `<div>Count: ${stats.messageCount}</div>`;
        statsHTML += `<div>Using SessionState: ${stats.usingSessionState ? 'Yes' : 'No'}</div>`;
      }
      
      // Session stats
      if (window.SessionMigration) {
        const stats = window.SessionMigration.getStats();
        statsHTML += `<div style="margin-top: 5px;"><b>Session:</b></div>`;
        statsHTML += `<div>Started: ${stats.sessionInfo.started ? 'Yes' : 'No'}</div>`;
        statsHTML += `<div>Messages: ${stats.sessionInfo.messageCount}</div>`;
      }
      
      // App stats
      if (window.AppStateMigration) {
        const stats = window.AppStateMigration.getStats();
        statsHTML += `<div style="margin-top: 5px;"><b>App State:</b></div>`;
        statsHTML += `<div>Current: ${stats.currentApp || 'None'}</div>`;
        statsHTML += `<div>Available: ${stats.availableApps}</div>`;
      }
      
      $('#migration-stats .dashboard-content').html(statsHTML || '<div>No statistics available</div>');
    },
    
    // Show dashboard
    show: function() {
      this.createDashboard();
      $('#migration-dashboard').fadeIn(200);
      this.isVisible = true;
      this.update();
      this.startAutoUpdate();
    },
    
    // Hide dashboard
    hide: function() {
      $('#migration-dashboard').fadeOut(200);
      this.isVisible = false;
      this.stopAutoUpdate();
    },
    
    // Toggle dashboard visibility
    toggle: function() {
      if (this.isVisible) {
        this.hide();
      } else {
        this.show();
      }
    },
    
    // Start auto-update
    startAutoUpdate: function() {
      if (this.updateInterval) return;
      
      this.updateInterval = setInterval(() => {
        this.update();
      }, this.updateFrequency);
    },
    
    // Stop auto-update
    stopAutoUpdate: function() {
      if (this.updateInterval) {
        clearInterval(this.updateInterval);
        this.updateInterval = null;
      }
    },
    
    // Toggle auto-update
    toggleAutoUpdate: function() {
      if (this.updateInterval) {
        this.stopAutoUpdate();
      } else {
        this.startAutoUpdate();
      }
      this.update();
    },
    
    // Manual refresh
    refresh: function() {
      this.update();
      console.log('[Dashboard] Manually refreshed');
    },
    
    // Initialize dashboard
    init: function() {
      // Add keyboard shortcut (Ctrl+Shift+M)
      document.addEventListener('keydown', (e) => {
        if (e.ctrlKey && e.shiftKey && e.key === 'M') {
          e.preventDefault();
          this.toggle();
        }
      });
      
      // Add console commands
      window.migrationDashboard = () => this.toggle();
      window.showDashboard = () => this.show();
      window.hideDashboard = () => this.hide();
      
      console.log('[Dashboard] Migration dashboard initialized. Press Ctrl+Shift+M to toggle.');
      
      // Auto-show in development if there are any issues
      if (window.location.hostname === 'localhost') {
        setTimeout(() => {
          if (window.MigrationConfig && window.MigrationConfig.enabled) {
            const consistency = window.MigrationConfig.checkConsistency();
            if (!consistency.consistent) {
              this.show();
              console.warn('[Dashboard] Showing dashboard due to consistency issues');
            }
          }
        }, 3000);
      }
      
      return this;
    }
  };
  
  // Initialize on load
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    window.MigrationDashboard.init();
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      window.MigrationDashboard.init();
    });
  }
  
})();