/**
 * Centralized UI Configuration
 * Contains all UI-related constants and configuration values
 */

// Breakpoint definitions (matching Bootstrap's grid system)
const UI_BREAKPOINTS = {
  MOBILE: 600,      // Below this is mobile mode
  TABLET: 768,      // Bootstrap's md breakpoint
  DESKTOP: 992,     // Bootstrap's lg breakpoint
  WIDE: 1200        // Bootstrap's xl breakpoint
};

// UI Animation and timing configurations
const UI_TIMING = {
  SCROLL_THRESHOLD: 100,           // Pixels to scroll before showing buttons
  RESIZE_DEBOUNCE: 250,            // Debounce for window resize
  RESIZE_OBSERVER_DEBOUNCE: 200,   // Debounce for ResizeObserver
  TOGGLE_ANIMATION: 200,            // Toggle button animation duration
  SCROLL_ANIMATION: 500,            // Scroll to top/bottom animation
  LAYOUT_FIX_DELAY: 100,           // Delay before fixing layout
  SPINNER_CHECK_INTERVAL: 1000     // Interval for checking spinner state
};

// Z-index layer management (higher numbers appear on top)
const UI_ZINDEX = {
  // Base layers
  BASE: 1,                    // Normal flow elements
  ELEVATED: 10,               // Slightly elevated elements
  
  // Content layers
  STICKY_HEADER: 100,         // Sticky headers
  DROPDOWN: 200,              // Dropdown menus
  
  // Overlay layers
  OVERLAY_BACKDROP: 1000,     // Menu overlay, backdrop
  OVERLAY_CONTENT: 1040,      // Overlay content (menus)
  SCROLL_BUTTONS: 1050,       // Scroll to top/bottom buttons
  
  // Modal layers
  MODAL_BACKDROP: 2000,       // Modal backdrop
  MODAL: 2010,                // Modal dialogs
  MODAL_DROPDOWN: 2020,       // Dropdowns inside modals
  
  // Critical layers
  TOOLTIP: 3000,              // Tooltips (highest regular content)
  NOTIFICATION: 4000,         // Important notifications
  CRITICAL: 9999              // Critical system messages (highest)
};

// UI State flags
const UI_STATE = {
  isStreaming: false,
  isMenuVisible: false,
  isResizing: false,
  previousWidth: null
};

// Check if we're in mobile mode
function isMobileView() {
  return $(window).width() < UI_BREAKPOINTS.MOBILE;
}

// Check if we're in tablet mode (menu/content exclusive)
function isTabletView() {
  return $(window).width() < UI_BREAKPOINTS.TABLET;
}

// Check if we're in desktop mode
function isDesktopView() {
  return $(window).width() >= UI_BREAKPOINTS.TABLET;
}

// Get current breakpoint name
function getCurrentBreakpoint() {
  const width = $(window).width();
  if (width < UI_BREAKPOINTS.MOBILE) return 'mobile';
  if (width < UI_BREAKPOINTS.TABLET) return 'tablet';
  if (width < UI_BREAKPOINTS.DESKTOP) return 'desktop';
  if (width < UI_BREAKPOINTS.WIDE) return 'desktop-lg';
  return 'wide';
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    UI_BREAKPOINTS,
    UI_TIMING,
    UI_ZINDEX,
    UI_STATE,
    isMobileView,
    isTabletView,
    isDesktopView,
    getCurrentBreakpoint
  };
}

// Make available globally for browser environment
window.UIConfig = {
  BREAKPOINTS: UI_BREAKPOINTS,
  TIMING: UI_TIMING,
  ZINDEX: UI_ZINDEX,
  STATE: UI_STATE,
  isMobileView,
  isTabletView,
  isDesktopView,
  getCurrentBreakpoint
};