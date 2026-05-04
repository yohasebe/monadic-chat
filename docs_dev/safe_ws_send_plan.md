# Safe WebSocket Send (`safeWsSend`) — design plan (H7 candidate)

> Status: **draft / awaiting approval** — 2026-05-04
>
> Sibling to `docs_dev/architecture_hardening_plan.md`. This document
> proposes the natural follow-on phase H7: "wrap `ws.send()` the way
> H3 wrapped `fetch()`."

## 1. The user-visible defect that motivated this

When the user opens the **Reset** modal:

- Clicking **Save to Knowledge Base** → alert
  `Could not send save request: Cannot read properties of null (reading 'send')`
- Clicking **Confirm** → silent failure, the reset never happens.

The error message comes from `utilities.js:1273-1276`. Both buttons fail
because both call bare `ws.send(...)` with no null/state guard, and
`ws` is the module-scope `let ws` declared at `websocket.js:24` which
is set to `null` by `closeCurrentWebSocket()` at `websocket.js:46`. If
the WebSocket dropped (network blip, idle close, page hibernation) and
the reconnect is still in flight, every `ws.send(...)` site in the
codebase hits the same null deref.

Save side: the throw is caught by `try/catch` and surfaced as an
alert. Reset side: no `try/catch`, the throw propagates and silently
dies — leaving the UI in the modal with no feedback at all.

## 2. The structural problem this is one symptom of

Repo-wide audit:

| Site count | Pattern |
|---:|---|
| 40 | `ws.send(...)` callsites in `public/js/**/*.js` |
| 1 | callsites that null-check `window.ws` before sending (`ws-tool-handler.js:64`) |
| 39 | callsites that crash on null `ws` |

This is **the same shape as the pre-H3 `fetch()` situation**. Before H3,
`fetch(...)` was strewn across the codebase, callers handled
auth/headers/JSON parsing inconsistently, and the X-Requested-With
contract drift produced a class of "JSON parse error" bugs. We solved
that by introducing `monadicFetch` and migrating callers.

The Reset/Save bug is the WebSocket equivalent. There is no central
`safeWsSend` helper, so 39 of 40 callsites silently inherit "you'd
better hope ws is non-null at click time."

## 3. The design

### 3.1 Helper API

New file: `public/js/monadic/monadic-ws.js` (sibling of
`monadic-fetch.js`, loaded immediately before `shims.js` and other
`ws-*` handler files in `scripts/build_js_bundle.mjs`).

```js
// Single source of truth for sending WebSocket messages.
// Handles: null ws, non-OPEN states, message-type-aware
// reconnect-and-replay, queue size cap, replay TTL, idempotency.
//
// Usage: replace
//   ws.send(JSON.stringify({ message: 'RESET' }));
// with
//   window.safeWsSend({ message: 'RESET' });
//
// Returns: { sent: boolean, queued?: boolean, state, error? }

window.safeWsSend(payload, opts);
```

`opts`:

| Field | Default | Meaning |
|---|---|---|
| `idempotent` | inferred from `payload.message` (see §3.3) | If true, may be queued for replay on reconnect. If false, fails fast on non-OPEN. |
| `alertOnFail` | `true` | Whether to surface a localised alert when the message cannot be sent. |
| `silentDrop` | `false` | Override: drop without alert (for `PING` and other internal background sends). |

Return value tells the caller whether to proceed with downstream UI
work (e.g. close modal) — the caller can branch on `sent` or use the
`{ sent: false }` shape to skip closing a dialog so the user does not
see an inconsistent state.

### 3.2 Decision tree

```
  payload arrives at safeWsSend
            │
            ▼
   inspect window.ws state
            │
   ┌────────┼────────┬─────────┬─────────┐
   ▼        ▼        ▼         ▼         ▼
 OPEN  CONNECTING  CLOSING   CLOSED    NULL
   │        │        │         │         │
 send     queue    queue     trigger  trigger
   │     for      for       reconnect reconnect
   │     onopen   onopen      │         │
   │        │        │       (opts.   (opts.
   │        │        │      idempotent? idempotent?)
   │        │        │       │ yes      │ yes
   │        │        │       └─ queue   └─ queue
   │        │        │         │ no       │ no
   │        │        │         └─ alert   └─ alert
   ▼        ▼        ▼         ▼         ▼
sent:true sent:false sent:false sent:false sent:false
queued:- queued:true queued:true queued:true queued:true
        (or false  (or false   (or false  (or false
         + alert)   + alert)    + alert)   + alert)
```

### 3.3 Idempotency classification (audit)

To decide which messages can be queued-and-replayed without server-
side duplication or surprising side-effects, every distinct outbound
message type is audited.

| Message type | Idempotent? | Why |
|---|---|---|
| `PING` | yes | Server-side just acks. |
| `RESET` | yes | Server resets session state to clean baseline. Repeating is a no-op. |
| `LOAD` | yes | Returns app/UI state. Pure read. |
| `HTML` | yes | Server emits the rendered DOM patch for current chat. Pure read. |
| `CHECK_TOKEN` | yes | Validates token; same token → same answer. |
| `CANCEL` | yes | Cancel a non-running task is a no-op. |
| `DELETE` | yes | `DELETE` for a `mid` that is already gone is a no-op (server returns "not found" gracefully). |
| `STOP_TTS` | yes | Stop a not-playing stream is a no-op. |
| `PRIVACY_REGISTRY` | yes | Returns the registry; pure read. |
| `LIBRARY_SAVE` | **yes** | `library_handler.rb` uses sticky `conversation_id` + delete-then-ingest (2026-05-02 dogfood polish). Replay produces same end state. |
| `LIBRARY_LIST` | yes | Pure read. |
| `LIBRARY_DELETE` | yes | Idempotent same as DELETE. |
| `LIBRARY_STATS` | yes | Pure read. |
| `LIBRARY_GET_CONVERSATION` | yes | Pure read by `conversation_id`. |
| `LIBRARY_RAG_QUERY` | yes | Pure read of session-scoped RAG flag. |
| `LIBRARY_RAG_TOGGLE` | yes | Toggle of session-scoped RAG flag; idempotent for same `enabled` value. |
| `LIBRARY_RENAME` | yes | Writes new title for `conversation_id`. Same value twice → same end state. |
| `LIBRARY_SET_SCOPE` | yes | Writes `scope_app` for `conversation_id`. Same value twice → same end state. |
| `EDIT` | yes | `handle_edit_message` overwrites `messages[idx]['text']` with `obj['content']`. Replay produces same end state. |
| `UPDATE_PARAMS` | yes | Server overwrites `session[:parameters]` with the supplied params hash. Same payload twice → same end state. |
| `UPDATE_LANGUAGE` | yes | Server overwrites the conversation language slot. Idempotent for same language. |
| `PDF_TITLES` | yes | Pure read of the per-app PDF document list. |
| `DELETE_PDF` | yes | Removes a named PDF document; second call is a no-op. |
| `DELETE_ALL_PDFS` | yes | Wipes the per-app store; second call is a no-op. |
| `LIBRARY_SUGGEST_TITLE` | **NO** | Triggers an LLM call via `TitleSuggester.suggest`; replay would burn another LLM call (cache is per-fingerprint, not per-replay). |
| `PRIVACY_EXPORT` | **NO** | Server re-runs encryption (with a fresh IV when encrypted) and streams a base64 download; replay would emit a second blob the UI would not be prepared to consume. |
| `SYSTEM_PROMPT` | **NO** | Server appends a new system message with a fresh `mid` to `session[:messages]`. Replay would push a duplicate. |
| `SAMPLE` | **NO** | Server appends a new turn with a fresh `mid` to `session[:messages]`. Replay would push a duplicate. |
| `AI_USER_QUERY` | **NO** | Triggers an LLM call to synthesize a user-side reply. Replay would burn a second call. |
| `CHAT` (user message — falls through to `handle_ws_streaming` with no `message` field set) | **NO** | Sending the same chat twice creates two messages and two LLM calls. |
| `PLAY_TTS` | **NO** | Triggers audio synthesis; replay would synthesize twice. |
| `TTS` | **NO** | Triggers cloud TTS synthesis (provider-billed); replay would emit a second audio stream the playback layer is not prepared to handle. |
| `AUDIO` | **NO** | Triggers STT transcription (provider-billed); replay would re-transcribe and double-insert into the input box. |

Anything not in the table defaults to non-idempotent (safer to fail
fast than to risk a silent double-send).

### 3.4 Queue semantics

- Queue lives on `window._wsSendQueue` (an array).
- Cap: 20 messages. When full, oldest non-essential entry (PING) is
  dropped first; if the queue is full of non-PING entries, new ones
  are rejected with `{ sent: false, error: 'queue full' }`.
- TTL: 30 seconds. On `onopen`, the queue is filtered: entries older
  than 30s are dropped with a debug log.
- Drain: on `onopen`, queued entries are sent in order via direct
  `ws.send` (NOT recursively through `safeWsSend`, to avoid loop).
- Dedup: identical payloads queued within 500ms are coalesced. (Stops
  rage-clicks from flooding the queue.)

### 3.5 Reconnect coordination

- Use existing `window._wsIsConnecting` flag. If a reconnect is
  already in flight, do not start another.
- If ws is `null` or `CLOSED`, call `window.connect_websocket()` (the
  established API) which will install the new ws on `window.ws` and
  fire `onopen` to drain the queue.
- If ws is `CONNECTING` or `CLOSING`, just queue and wait for the
  existing transition.

### 3.6 Failure surface

Messages reach the user in three modes, in priority order:

1. **`sent: true`** — silent success, normal flow.
2. **`sent: false, queued: true`** — show a small toast
   `<i class='fa-solid fa-spinner fa-spin'></i> Reconnecting…`
   (auto-clears when queue drains). No modal.
3. **`sent: false, queued: false`** — show an alert
   `Connection lost. Please retry.` (i18n key
   `ui.messages.wsSendFailed`). Caller chooses whether to close the
   parent modal.

For background sends (PING, PRIVACY_REGISTRY) we pass
`{ silentDrop: true }` so failure mode #3 does not spam the user with
alerts when ws is briefly down.

## 4. Phased rollout

Modeled on H5 sweep migration. One phase per commit; each commit is
revertable in isolation.

| Phase | Scope | Risk | Touch | Status |
|---|---|---|---|---|
| H7.1 | Add `monadic-ws.js` + unit tests + register in bundle order | low | 3 files | pending |
| H7.2 | Migrate the 3 `utilities.js` sites (the user-reported bug) | low (covered by H7.1 unit tests + manual reset/save smoke) | 1 file | pending |
| H7.3 | Migrate `cards.js` (DELETE × 8, STOP_TTS, PLAY_TTS, EDIT, REFRESH — 12 sites) | low | 1 file | pending |
| H7.4 | Migrate `alert-manager.js` (DELETE × 3) | low | 1 file | pending |
| H7.5 | Migrate `library-panel.js` `send()` helper (covers all LIBRARY_* messages) | low | 1 file | pending |
| H7.6 | Migrate `ws-*` handlers (PING × 2, PRIVACY_REGISTRY, PRIVACY_EXPORT, HTML — 5 sites across 4 files) | low | 4 files | pending |
| H7.7 | Migrate `monadic.js` (12 sites; includes the only **non-idempotent** sends — CHAT/AI_USER_QUERY/SYSTEM_PROMPT/SAMPLE/initiate-from-assistant) | medium | 1 file | pending |
| H7.8 | Migrate `recording.js` (AUDIO), `tts.js` (TTS), `websocket.js` (CHECK_TOKEN, internal LOAD) | low | 3 files | pending |
| H7.9 | Add lint rule `check_bare_ws_send.rb` to catch new bare `ws.send` outside the helper file. Self-check entry. | low | 2 files | pending |

After H7.9 the lint suite has 5 enforcement rules + self-check, baselines all 0.

## 5. Tests

### Unit tests (Jest)

`test/frontend/monadic-ws.test.js`:

1. `safeWsSend` returns `sent: true` when `window.ws.readyState === OPEN`.
2. Returns `sent: false, queued: true` when state is `CONNECTING`.
3. Returns `sent: false, queued: true` and triggers reconnect when `ws` is null and message is idempotent.
4. Returns `sent: false, queued: false` when message is non-idempotent and state is non-OPEN.
5. Drains queue in FIFO order on `onopen`.
6. Drops PING entries first when queue exceeds cap.
7. Coalesces duplicate payloads queued within 500ms.
8. TTL: drops entries older than 30s on drain.
9. Calls `alert` only when `alertOnFail !== false`.
10. Honors `silentDrop` for background sends (no alert, no queue).

### Integration smoke (manual, documented in `docs_dev/safe_ws_send_plan.md`)

- Open the app. Open DevTools → Network → "Offline".
- Click Reset → Save: expect "Reconnecting…" toast, then on Online
  toggle the message goes through and the save success appears.
- Click Reset → Confirm: expect same behavior; the reset completes
  after reconnect.
- Send a chat message while offline: expect "Connection lost. Please
  retry." alert, the user message stays in the input box.

### Lint (after H7.9)

`scripts/lint/check_bare_ws_send.rb` — flags any `ws.send(`,
`window.ws.send(` outside `monadic-ws.js`. Empty allowlist after H7.9.
Self-check meta-test verifies the rule fires on a deliberate fixture.

## 6. Risk register

| ID | Risk | Mitigation |
|---|---|---|
| R1 | Idempotency miscategorization → server-side duplicate. | Lean conservative: classify as non-idempotent unless proven safe via server handler audit. |
| R2 | Reconnect storm if many sends queue concurrently. | Reuse existing `window._wsIsConnecting` flag; only one connect at a time. |
| R3 | Queue grows unbounded if reconnect never succeeds. | Cap (20) + TTL (30s) + PING drop priority. |
| R4 | Replay order vs server expectation (e.g. RESET then LOAD must stay in order). | FIFO drain. Both messages idempotent so order matters but is preserved. |
| R5 | Cross-test pollution: queue state leaks between Jest tests. | `beforeEach` resets `window._wsSendQueue` and `window.ws`. |
| R6 | `connect_websocket` callback timing: `onopen` may fire before queue is drained, or after another close. | Drain inside `onopen` synchronously; on subsequent close, retain queue and re-drain on next open. |
| R7 | Lint false positive on the helper file itself. | `ACCEPTED_FILES` in lint script matching H2 pattern. |
| R8 | User keeps clicking Reset while reconnect is pending → multiple RESETs queued. | Coalesce duplicate payloads (§3.4). |

## 7. Cost / benefit

**Cost:**
- 9 phases ≈ 9 small commits over 2-3 sessions.
- Helper + tests ≈ 200 lines of new code.
- Lint rule ≈ 80 lines.
- Audit + idempotency table maintenance.

**Benefit:**
- Eliminates the *class* of "operation silently failed because ws was null" bugs.
- Closes the symmetry gap with H3 (`monadicFetch`): all I/O surfaces now have a guarded helper.
- Anti-pattern lint extends to 5 rules, baselines all 0.
- Documents idempotency contract per message — useful artifact for future server changes.
- The user's specific Reset/Save bug is fixed in H7.2 (small, isolated commit) without waiting for full sweep.

## 8. Decision

Proceed if the user agrees this is worth a multi-session H7 phase.
Land H7.1 + H7.2 in one session as the minimum viable fix (covers the
user-reported defect and proves the helper). Subsequent phases can
land at any cadence the user prefers.

If the user wants the immediate symptom fixed without committing to
H7, fall back to plan A (3-line null-guard inserts in `utilities.js`)
and revisit later.
