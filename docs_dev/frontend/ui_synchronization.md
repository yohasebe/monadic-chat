# UI State Synchronization

When the user switches apps, changes the model or loads parameters, several parts of the UI have to follow: the model dropdown, the parameter controls, the reasoning controls and the `#model-selected` badge. This page lists where each is updated and the rules for changing that code.

## Where Updates Happen

| Trigger | Code | Updates |
|---|---|---|
| Parameters from the server or an import | `window.loadParams(params, calledFor)` (`utilities.js`) | Controls from `params`; the badge for `calledFor === "loadParams"` |
| App selected | `window.proceedWithAppChange(appValue)` (`monadic.js`) | Model list (`getModelsForApp`), default model, controls, badge |
| Model selected | `change` handler of `#model` (`monadic.js`) | Reasoning controls (`window.reasoningUIManager.updateUI(provider, model)`), badge |
| Reasoning effort changed | `change` handler of `#reasoning-effort` (`monadic.js`) | Badge |
| Reset | `doResetActions()` (`utilities.js`) | Controls back to the app's defaults, badge |

The badge text is `Provider (model)`, or `Provider (model - effort)` when the model's spec has `reasoning_effort`. Each of the places above writes it directly.

`ReasoningUIManager` (`reasoning-ui-manager.js`, `window.reasoningUIManager`) builds the reasoning controls for the provider and model: `updateUI(provider, model)`, `hideAllUIs()`, `getValue()`, `setValue(value, type)`.

## Rules

- Update dependent UI explicitly in the function that changes the state; do not rely on a chain of dispatched `change` events.
- After code that rebuilds a part of the DOM (the reasoning controls, the model list), write the badge last.
- When an update must wait for the current event handlers to finish, defer it with `setTimeout(…, 0)`.
- Use `$id()` and the other helpers in `dom-helpers.js` for DOM access.

## Debugging

```javascript
$id('model').addEventListener('change', function () {
  console.log('[SYNC] model change', { selected: this.value, at: Date.now() });
});

console.log({
  dropdown: $id('model')?.value,
  badge: $id('model-selected')?.textContent
});
```

Browser DevTools: the Performance tab shows the order of events, the Elements tab shows DOM changes as they happen.

## Related Files

- `docker/services/ruby/public/js/monadic/utilities.js` (`loadParams`, `doResetActions`)
- `docker/services/ruby/public/js/monadic.js` (`proceedWithAppChange`, change handlers)
- `docker/services/ruby/public/js/monadic/reasoning-ui-manager.js`
- `docker/services/ruby/public/js/monadic/model_utils.js` (`getModelsForApp`)
