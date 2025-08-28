/**
 * Performance Monitoring Module
 * Tracks and reports performance metrics for optimization
 */

(function(window) {
  'use strict';
  
  // Performance metrics storage
  const metrics = {
    pageLoadTime: 0,
    domReadyTime: 0,
    resourceLoadTime: 0,
    functionTimings: new Map(),
    renderMetrics: [],
    memoryUsage: []
  };
  
  // Configuration
  const config = {
    enabled: window.DEBUG_MODE || false,
    sampleRate: 1000, // Memory sampling rate in ms
    maxMetrics: 100   // Maximum metrics to store
  };
  
  /**
   * Initialize performance monitoring
   */
  function initialize() {
    if (!config.enabled) return;
    
    // Measure page load performance
    if (window.performance && window.performance.timing) {
      const timing = window.performance.timing;
      metrics.pageLoadTime = timing.loadEventEnd - timing.navigationStart;
      metrics.domReadyTime = timing.domContentLoadedEventEnd - timing.navigationStart;
      metrics.resourceLoadTime = timing.loadEventEnd - timing.responseEnd;
    }
    
    // Start memory monitoring if available
    if (window.performance && window.performance.memory) {
      startMemoryMonitoring();
    }
    
    console.log('Performance monitoring initialized');
  }
  
  /**
   * Measure function execution time
   * @param {string} name - Function name for tracking
   * @param {Function} fn - Function to measure
   * @returns {*} Function result
   */
  function measure(name, fn) {
    if (!config.enabled) return fn();
    
    const startTime = performance.now();
    const result = fn();
    const endTime = performance.now();
    const duration = endTime - startTime;
    
    // Store timing
    if (!metrics.functionTimings.has(name)) {
      metrics.functionTimings.set(name, []);
    }
    
    const timings = metrics.functionTimings.get(name);
    timings.push(duration);
    
    // Keep only last N measurements
    if (timings.length > config.maxMetrics) {
      timings.shift();
    }
    
    // Log slow functions
    if (duration > 100) {
      console.warn(`Slow function: ${name} took ${duration.toFixed(2)}ms`);
    }
    
    return result;
  }
  
  /**
   * Measure async function execution time
   * @param {string} name - Function name for tracking
   * @param {Function} fn - Async function to measure
   * @returns {Promise<*>} Function result
   */
  async function measureAsync(name, fn) {
    if (!config.enabled) return fn();
    
    const startTime = performance.now();
    const result = await fn();
    const endTime = performance.now();
    const duration = endTime - startTime;
    
    // Store timing
    if (!metrics.functionTimings.has(name)) {
      metrics.functionTimings.set(name, []);
    }
    
    const timings = metrics.functionTimings.get(name);
    timings.push(duration);
    
    // Keep only last N measurements
    if (timings.length > config.maxMetrics) {
      timings.shift();
    }
    
    // Log slow async functions
    if (duration > 500) {
      console.warn(`Slow async function: ${name} took ${duration.toFixed(2)}ms`);
    }
    
    return result;
  }
  
  /**
   * Start monitoring memory usage
   */
  function startMemoryMonitoring() {
    if (!config.enabled || !window.performance.memory) return;
    
    setInterval(() => {
      const memory = window.performance.memory;
      metrics.memoryUsage.push({
        timestamp: Date.now(),
        usedJSHeapSize: memory.usedJSHeapSize,
        totalJSHeapSize: memory.totalJSHeapSize,
        jsHeapSizeLimit: memory.jsHeapSizeLimit
      });
      
      // Keep only last N measurements
      if (metrics.memoryUsage.length > config.maxMetrics) {
        metrics.memoryUsage.shift();
      }
      
      // Warn if memory usage is high
      const usagePercent = (memory.usedJSHeapSize / memory.jsHeapSizeLimit) * 100;
      if (usagePercent > 90) {
        console.warn(`High memory usage: ${usagePercent.toFixed(1)}%`);
      }
    }, config.sampleRate);
  }
  
  /**
   * Mark a render event
   * @param {string} component - Component that rendered
   */
  function markRender(component) {
    if (!config.enabled) return;
    
    metrics.renderMetrics.push({
      component,
      timestamp: performance.now()
    });
    
    // Keep only last N renders
    if (metrics.renderMetrics.length > config.maxMetrics) {
      metrics.renderMetrics.shift();
    }
  }
  
  /**
   * Get performance report
   * @returns {Object} Performance metrics summary
   */
  function getReport() {
    const report = {
      pageLoad: {
        total: metrics.pageLoadTime + 'ms',
        domReady: metrics.domReadyTime + 'ms',
        resources: metrics.resourceLoadTime + 'ms'
      },
      functions: {},
      memory: null,
      renders: metrics.renderMetrics.length
    };
    
    // Calculate function statistics
    metrics.functionTimings.forEach((timings, name) => {
      if (timings.length > 0) {
        const avg = timings.reduce((a, b) => a + b, 0) / timings.length;
        const max = Math.max(...timings);
        const min = Math.min(...timings);
        
        report.functions[name] = {
          calls: timings.length,
          avg: avg.toFixed(2) + 'ms',
          max: max.toFixed(2) + 'ms',
          min: min.toFixed(2) + 'ms'
        };
      }
    });
    
    // Add memory statistics if available
    if (metrics.memoryUsage.length > 0) {
      const latest = metrics.memoryUsage[metrics.memoryUsage.length - 1];
      report.memory = {
        used: (latest.usedJSHeapSize / 1024 / 1024).toFixed(2) + 'MB',
        total: (latest.totalJSHeapSize / 1024 / 1024).toFixed(2) + 'MB',
        limit: (latest.jsHeapSizeLimit / 1024 / 1024).toFixed(2) + 'MB',
        usage: ((latest.usedJSHeapSize / latest.jsHeapSizeLimit) * 100).toFixed(1) + '%'
      };
    }
    
    return report;
  }
  
  /**
   * Log performance report to console
   */
  function logReport() {
    if (!config.enabled) return;
    
    console.group('Performance Report');
    const report = getReport();
    console.table(report.pageLoad);
    if (Object.keys(report.functions).length > 0) {
      console.table(report.functions);
    }
    if (report.memory) {
      console.table(report.memory);
    }
    console.log(`Total renders: ${report.renders}`);
    console.groupEnd();
  }
  
  /**
   * Enable or disable monitoring
   * @param {boolean} enabled - Enable state
   */
  function setEnabled(enabled) {
    config.enabled = enabled;
    console.log(`Performance monitoring ${enabled ? 'enabled' : 'disabled'}`);
  }
  
  /**
   * Clear all metrics
   */
  function clear() {
    metrics.functionTimings.clear();
    metrics.renderMetrics = [];
    metrics.memoryUsage = [];
    console.log('Performance metrics cleared');
  }
  
  // Public API
  const PerformanceMonitor = {
    initialize,
    measure,
    measureAsync,
    markRender,
    getReport,
    logReport,
    setEnabled,
    clear
  };
  
  // Export to window
  window.PerformanceMonitor = PerformanceMonitor;
  
  // Auto-initialize when document is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialize);
  } else {
    initialize();
  }
  
  // Add console command for easy access
  window.perfReport = logReport;
  
  // Export for testing
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = PerformanceMonitor;
  }
  
})(typeof window !== 'undefined' ? window : this);