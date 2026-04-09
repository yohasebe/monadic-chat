# UI State Synchronization

This document explains UI state synchronization patterns and known issues in the Monadic Chat frontend.

## Overview

Monadic Chat's frontend manages complex state across multiple UI components:
- Model selection dropdowns
- Parameter forms (temperature, max_tokens, etc.)
- Reasoning/thinking UI toggles
- Message cards and streaming displays
- Status badges and indicators

These components must stay synchronized when users switch apps, change models, or modify settings.

## Synchronization Architecture

### State Flow

```
User Action → loadParams() → DOM Updates → Event Triggers → UI Component Updates
```

**Key Functions:**
- `loadParams()`: Loads app/model parameters into UI (utilities.js)
- `showReasoningUI()` / `hideReasoningUI()`: Toggle reasoning display
- `updateModelSelectedBadge()`: Update model selection indicator
- Event handlers: Native `change` events on form inputs via `addEventListener`

## Known Synchronization Issues

### Model Selected Badge Update Timing

**Problem**: The `#model-selected` badge doesn't update immediately when switching apps.

**Root Cause**:
- `loadParams()` selects the default model option
- This fires a `change` event that updates reasoning UI components
- Reasoning UI update modifies DOM structure, sometimes overriding model badge update
- Timing race condition: badge update vs reasoning UI DOM modifications

**Example Failure Scenario:**
```javascript
// In loadParams()
const modelEl = document.getElementById('model');
modelEl.value = defaultModel;
modelEl.dispatchEvent(new Event('change', { bubbles: true }));

// Change handler updates reasoning UI
modelEl.addEventListener('change', function() {
  showReasoningUI();  // Modifies DOM
  updateBadge();      // May get overridden if reasoning UI touches badge area
});
```

**Solution (Recommended)**: Use `setTimeout(..., 0)` for deferred badge update

```javascript
function loadParams() {
  // ... load all parameters ...
  const modelEl = document.getElementById('model');
  modelEl.value = defaultModel;

  // Ensure badge updates after all DOM modifications
  setTimeout(() => {
    const selectedEl = document.getElementById('model-selected');
    if (selectedEl) selectedEl.textContent = modelEl.value;
  }, 0);
}
```

## Best Practices

### 1. Explicit State Updates

Prefer explicit update functions over relying on event propagation:

```javascript
// ✅ Good: Explicit
function switchApp(appName) {
  loadAppConfig(appName);
  updateModelDropdown();
  updateParameterForm();
  updateBadges();
}

// ❌ Risky: Event-dependent
function switchApp(appName) {
  loadAppConfig(appName);  // Hopes events will update everything
}
```

### 2. Use `setTimeout(..., 0)` for Post-Render Updates

When DOM modifications from event handlers may conflict:

```javascript
function criticalUpdate() {
  modifyDOM();

  // Ensure dependent updates happen after current render cycle
  setTimeout(() => {
    updateDependentUI();
  }, 0);
}
```

### 3. Avoid Event Handler Chains

Deep event chains make timing issues hard to debug:

```javascript
// ❌ Fragile: Chain of events
inputA.addEventListener('change', () => {
  inputB.dispatchEvent(new Event('change', { bubbles: true }));
});

inputB.addEventListener('change', () => {
  inputC.dispatchEvent(new Event('change', { bubbles: true }));
});

// ✅ Better: Explicit orchestration
function updateAllInputs() {
  updateInputA();
  updateInputB();
  updateInputC();
}
```

## Debugging Synchronization Issues

### 1. Check Event Order

```javascript
document.getElementById('model').addEventListener('change', function() {
  console.log('[SYNC] Model change event fired', {
    selected: this.value,
    timestamp: Date.now()
  });
});
```

### 2. Verify DOM State

```javascript
function debugModelSelection() {
  const modelEl = document.getElementById('model');
  const badgeEl = document.getElementById('model-selected');
  console.log({
    dropdownValue: modelEl ? modelEl.value : null,
    badgeText: badgeEl ? badgeEl.textContent : null
  });
}
```

### 3. Use Browser DevTools

- **Performance tab**: Record timeline to see event sequence
- **Elements tab**: Watch DOM mutations in real-time
- **Console**: Add breakpoints in event handlers

## Related Files

- `docker/services/ruby/public/js/monadic/utilities.js`: `loadParams()` implementation
- `docker/services/ruby/public/js/monadic.js`: Main app logic, event handlers
- `docker/services/ruby/public/js/monadic/badge-renderer.js`: Badge update logic
