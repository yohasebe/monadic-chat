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
- `loadParams()`: Loads app/model parameters into UI (websocket.js)
- `showReasoningUI()` / `hideReasoningUI()`: Toggle reasoning display
- `updateModelSelectedBadge()`: Update model selection indicator
- Event handlers: jQuery `change` events on form inputs

## Known Synchronization Issues

### Model Selected Badge Update Timing

**Problem**: The `#model-selected` badge doesn't update immediately when switching apps.

**Root Cause**:
- `loadParams()` triggers `#model option:first.prop('selected', true)` to select the default model
- This fires a jQuery `change` event that updates reasoning UI components
- Reasoning UI update modifies DOM structure, sometimes overriding model badge update
- Timing race condition: badge update vs reasoning UI DOM modifications

**Example Failure Scenario:**
```javascript
// In loadParams()
$('#model option').prop('selected', false);
$('#model option:first').prop('selected', true);  // Fires 'change' event

// Change handler updates reasoning UI
$('#model').on('change', function() {
  showReasoningUI();  // Modifies DOM
  updateBadge();      // May get overridden if reasoning UI touches badge area
});
```

**Solution A (Recommended)**: Create Dedicated `updateModelSelectedBadge()` Helper

```javascript
function updateModelSelectedBadge() {
  const selectedModel = $('#model option:selected').text();
  $('#model-selected').text(selectedModel);
}

// Call explicitly after loadParams completes
function loadParams() {
  // ... load all parameters ...
  $('#model option:first').prop('selected', true);

  // Ensure badge updates after all DOM modifications
  setTimeout(() => {
    updateModelSelectedBadge();
  }, 0);
}
```

**Benefits:**
- ✅ Explicit control over badge updates
- ✅ Decouples from option selection timing
- ✅ Can be called after all DOM modifications complete
- ✅ Easy to debug and test

**Solution B (Minimal)**: Add `trigger('change')` at End of `loadParams()`

```javascript
function loadParams() {
  // ... load all parameters ...
  $('#model option:first').prop('selected', true);

  // Force synchronization after all loadParams operations
  $('#model').trigger('change');
}
```

**Trade-offs:**
- ✅ Less invasive, minimal code changes
- ❌ Couples timing to change event propagation
- ❌ May trigger unwanted side effects if change handler does more than badge update

**Implementation Guidance**: Prefer Solution A for deterministic updates; Solution B remains available when event-driven propagation is acceptable.

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
$('#input-a').on('change', () => {
  $('#input-b').trigger('change');  // Fires another handler
});

$('#input-b').on('change', () => {
  $('#input-c').trigger('change');  // And another...
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

Add logging to understand event firing sequence:

```javascript
$('#model').on('change', function() {
  console.log('[SYNC] Model change event fired', {
    selected: $(this).val(),
    timestamp: Date.now()
  });
});
```

### 2. Verify DOM State

Check actual DOM state vs expected state:

```javascript
function debugModelSelection() {
  console.log({
    dropdownValue: $('#model').val(),
    badgeText: $('#model-selected').text(),
    selectedOption: $('#model option:selected').text()
  });
}
```

### 3. Use Browser DevTools

- **Performance tab**: Record timeline to see event sequence
- **Elements tab**: Watch DOM mutations in real-time
- **Console**: Add breakpoints in event handlers

## Related Files

- `docker/services/ruby/public/js/monadic/websocket.js`: `loadParams()` implementation
- `docker/services/ruby/public/js/monadic/ui/reasoning.js`: Reasoning UI updates
- `docker/services/ruby/public/js/monadic/ui/badges.js`: Badge update logic (if exists)
