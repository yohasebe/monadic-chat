# Privacy Filter (PII Masking)

## Overview

The Privacy Filter masks personally identifiable information (PII) in user messages before they are sent to AI providers, then restores the original values in the AI's response on the way back. Detection runs locally in a separate Docker container (Microsoft Presidio + spaCy) so PII never leaves your machine on its way to or from the LLM.

The Privacy container is part of Monadic Chat's default container set, so the feature is ready to use the first time you start the app. Each app's per-session toggle starts off and must be turned on to enable masking for that conversation.

## When to Use It

- Drafting emails or documents that mention real names, email addresses, or phone numbers.
- Translating text that contains personal information.
- Sharing snippets that include sensitive identifiers without rewriting them by hand.

## Installation

The Privacy container is built and started automatically with the rest of Monadic Chat. All supported language models are included in the image; English is mandatory and always enabled.

To enable masking for non-English content, turn on additional languages:

1. Open **Actions → Install Options**.
2. Locate the **Privacy Filter — Additional Languages** section.
3. Check the languages you want from German (de), Spanish (es), French (fr), Italian (it), Japanese (ja), Dutch (nl), Portuguese (pt), Chinese (zh). English is always present and cannot be unchecked.
4. Click **Save**. No rebuild is involved — a running Privacy container is restarted with the new language set automatically. If the Monadic Chat server is currently running, restart it (Stop/Start) so the per-session toggle recognizes the newly enabled languages.

Language selection is a runtime setting: enabling or disabling a language changes which models the server loads, not the container image.

Runtime opt-out: set `PRIVACY_FILTER=false` in `~/monadic/config/env` to skip the Privacy container entirely. The toggle becomes disabled with the tooltip "Privacy Filter is disabled." until the env value is restored.

## Per-Session Toggle

Once the container is installed, apps that support privacy filtering show a **Privacy Filter** toggle in the Session Controls panel. The toggle is unchecked at the start of every session.

- Turn it on before sending the first message to enable masking for the session.
- After the first message is sent the toggle locks. Pressing **Reset** or switching to a different app re-enables editing.
- Your last choice is remembered per app, so switching back to an app restores its previous toggle state.

When the toggle is disabled, hovering over it shows the reason:

- *This app does not support Privacy Filter.* — The app's MDSL does not declare a `privacy` block.
- *Privacy Filter is disabled.* — `PRIVACY_FILTER=false` is set in the environment, so the Privacy container was not started.
- *Privacy Filter is not installed for this language. Install via Install Options.* — The sidebar's conversation_language is not among the currently enabled Presidio languages. Enable the language in Actions → Install Options (applies on save), or change the conversation_language to one that is enabled.

## Language Selection

The session toggle's enabled state and the masking language follow the sidebar **conversation_language**:

| Sidebar conversation_language | Masking language | Toggle |
|---|---|---|
| Automatic | English | enabled |
| English (en) | English | enabled |
| An installed non-English language (e.g. ja, de, fr) | That language (matching spaCy NER model) | enabled |
| An uninstalled language (e.g. Korean) | — | disabled with tooltip |

**Recommendation**: when masking non-English content, set the conversation_language explicitly in the sidebar. The "Automatic" option always masks as English regardless of the actual content, which can miss culture-specific entities (e.g. Japanese names + honorific trimming).

Japanese has additional dedicated handling: when `lang_used` is `ja`, the Privacy container trims trailing honorifics (`さん`, `様`, `先生`, `君`, etc.) from PERSON spans so that placeholders capture only the actual name.

## Indicator and Registry

When the filter is active, the chat header shows an indicator:

- **Privacy ready** (gray unlock icon): the filter is on but no entities have been masked yet.
- **Privacy ON (N)** (green lock icon with count): N placeholders are currently registered for restoration.
- **Privacy error** (red): the privacy container could not be reached. Check that Docker is running and the container is healthy.

When the conversation_language is set to **Automatic**, a small language badge appears next to the indicator (for example, **🌐 ja**) once the first reliably-detectable user message has locked the session to a specific language. The badge does not appear until a lock is in place; sidebar-selected languages are already explicit in the dropdown so the badge is omitted.

Clicking the indicator opens the **Registry Viewer**, which lists each placeholder, the original value, and the entity type (PERSON, EMAIL_ADDRESS, and so on). The registry is held in session memory only; it is never written to the conversation log on disk.

## Unmask Highlight

Conversation cards (both user input and assistant replies) underline every value that the Privacy Filter is currently tracking. The same placeholder always uses the same color — for example, every occurrence of the same person's name draws the same blue underline across every card, while a different name uses a different color. The background stays gray; only the underline color changes, so the layout is not visually busy.

Hover any underlined value to see the placeholder it travelled through (for example, *Tracked as <<PERSON_1>>*). The wrap is applied after markdown rendering and skips `<code>`, `<pre>`, and `<a>` subtrees so syntax-highlighted blocks and link text are never modified.

The highlight is purely visual; it never changes the LLM payload. The same value passes through the registry-aware masking pipeline whether or not it is highlighted.

## What Gets Masked

By default the filter masks the following entity types:

`PERSON`, `EMAIL_ADDRESS`, `PHONE_NUMBER`, `CREDIT_CARD`, `IP_ADDRESS`, `IBAN_CODE`, `US_SSN`, `MEDICAL_LICENSE`, `URL`.

Common but noisy types such as `LOCATION` ("Tokyo") and `DATE_TIME` ("Friday") are excluded from the default set so everyday phrasing is not masked.

App authors can adjust the entity list in MDSL:

```ruby
privacy do
  enabled true
  mask_types :person, :email, :address  # adding :address re-includes LOCATION
end
```

## Text-to-Speech (TTS) Sanitization

When the Privacy Filter is active, TTS playback (the per-card **Play** button, the Auto-Speech path, and the system **TTS** test) replaces tracked PII with the same short labels the streaming buffer uses (for example, "PERSON 1", "EMAIL ADDRESS 1"). This applies to every TTS provider — cloud TTS APIs (OpenAI, Gemini, ElevenLabs, etc.) never receive original names, addresses, or phone numbers, and listeners do not have to sit through long email addresses character-by-character.

The Web Speech API path (browser-native synthesis) goes through the same sanitizer. Even though the audio is produced locally, the text passed to the synth is identical to what a cloud provider would receive, keeping the UX consistent.

## Knowledge Base Save and Search

Privacy Filter and Knowledge Base save are **mutually exclusive at the app level** — see [Privacy Filter and Knowledge Base by App](../basic-usage/basic-apps.md#privacy-kb-by-app) for the three-group allocation rationale and the complete table. In privacy-aware apps the Save button stays visible but is disabled with a tooltip explaining why, mirroring how the Privacy Filter session toggle is shown disabled on apps that don't support it; in artifact-centric apps the Knowledge Base panel is hidden entirely.

To preserve a conversation handled in a privacy-aware app, use **Privacy Export** (encryption + optional masked-only mode) — see the section below.

The Browse modal shows a muted ⚠️ icon in front of an entry's title when the title or source contains an obvious email or phone-number pattern. This is a lightweight regex heuristic that costs O(rows) per render and helps spot legacy entries that may carry PII even though the current app allocation rule prevents new ones from being saved that way.

### `library_search` retrieval

When the Privacy Filter is active in a session that calls `library_search`, the retrieved snippets pass through the same Privacy Pipeline before they reach the LLM. Any PII present in the Knowledge Base is masked into placeholders for the request, and the LLM's reply is restored on the way back via the existing streaming-handler pass.

This closes a back-channel that would otherwise let saved PII reach the LLM via retrieval, even though the user enabled the Privacy Filter for the current session. The masking is best-effort — if the pipeline raises, the tool falls back to the raw snippet rather than failing the search.

### Global vs App-only scope

Saving a conversation as **Global** (rather than the default **App-only**) makes the entry retrievable from every app in this Monadic Chat install via `library_search`. The save dialog now shows an inline warning when Global is selected, reminding you that future apps you have not yet picked can also retrieve the content. Prefer App-only unless the conversation is intentionally meant to be shared across apps.

## Encrypted Export

When the Privacy Filter has masked at least one entity in the current session, the **Export** button opens a unified export dialog with two orthogonal axes:

- **Encryption**: encrypt the file with AES-256-GCM (Argon2id key derivation) using a passphrase you provide.
- **Content**: export the conversation either with original values restored or with placeholders kept in place.

When Privacy is active in the session, the dialog defaults to **Masked** content so an accidental click does not write plaintext PII to disk. You can still pick **Restored** explicitly; that combination — Restored content with no encryption — triggers a red warning banner explaining what is about to land in the file. Files that end up containing plaintext PII are tagged with a `-PRIVATE` suffix in the filename so they are easy to spot in a downloads folder.

Common combinations:

1. **Encrypted + Restored** — a personal archive that can only be opened by you.
2. **Encrypted + Masked** — share analysis logs without exposing PII even after decryption.
3. **Plain + Masked** — quick sharable example with no real names.
4. **Plain + Restored** — flagged with `-PRIVATE` and the strongest warning; intended for trusted, local-only workflows.

Passphrase requirements: minimum 8 characters and the confirmation field must match. The strength meter is informational only and does not block submission.

To re-open an encrypted export, use the **Import** button and enter the passphrase when prompted. The registry is restored alongside the conversation so subsequent messages continue to mask consistently.

## Document DB Export and Import (Actions menu) :id=document-db-export-import

The **Actions → Export Document DB** and **Actions → Import Document DB** menu items operate on the entire qdrant volume — every saved conversation, PDF, and Knowledge Base entry. Both items now show a confirmation dialog before proceeding.

For export, you can choose between:

- **Encrypt and Export** (default): prompts for a passphrase, encrypts the tarball with AES-256-GCM (PBKDF2-SHA256, 600 000 iterations) over a per-export salt, and writes `monadic-qdrant.tar.gz.enc` to the shared folder. The plaintext tarball is removed after a successful encryption pass.
- **Export Plain**: writes the unencrypted tarball directly. The dialog warns that the file contains every saved conversation and PDF in plaintext regardless of whether the Privacy Filter was active when each item was saved.

Import detects the file extension automatically: `.tar.gz` is unpacked as before; `.tar.gz.enc` prompts for the passphrase, decrypts to a temporary plaintext file, runs the qdrant volume import, and removes the temporary file. A wrong passphrase or tampered ciphertext fails decryption (the tarball is never partially unpacked) and the qdrant volume is left untouched.

Encryption format: `[magic 'MQDB'] [version 0x01] [salt 16] [iv 12] [ciphertext] [authTag 16]`, streaming-friendly so multi-GB volumes do not need to fit in memory.

## Supported Apps

The Privacy Filter is enabled in the MDSL definitions of these apps:

- Mail Composer
- Chat Plus
- Translate
- Second Opinion

Other apps do not declare `privacy do` and the toggle stays disabled. Apps that primarily generate code, media, or speech were excluded because masking would interfere with their core output (placeholders inside generated code, for example, would not be useful).

## Limitations

- Custom recognizers live in the privacy container source (`docker/services/privacy/recognizers/`). Adding new recognizers requires rebuilding the container.
- Masking adds a small per-message latency, typically 50-200 ms depending on text length. Each turn re-masks the entire context (user and past assistant messages alike) so the registry stays consistent across turns.
- Supported masking languages are limited to the nine spaCy NER models bundled with Presidio: English, German, Spanish, French, Italian, Japanese, Dutch, Portuguese, Chinese. Languages outside this set (e.g. Korean, Arabic) cannot use the Privacy Filter — the session toggle is disabled when the sidebar conversation_language is one of them.

## Configuration Reference

Settings stored in `~/monadic/config/env`:

| Variable | Values | Default | Description |
|---|---|---|---|
| `PRIVACY_FILTER` | `true` / `false` | `true` | Runtime gate. Set to `false` to skip starting the privacy container at startup; the toggle becomes disabled until restored to `true`. |
| `PRIVACY_LANGS` | comma-separated language codes | `en` | Languages the privacy server loads at startup (all models are included in the image). English is mandatory and prepended automatically. The preferred edit path is Actions → Install Options → "Privacy Filter — Additional Languages"; advanced users can edit the env file directly. Supported codes: `en`, `de`, `es`, `fr`, `it`, `ja`, `nl`, `pt`, `zh`. |
| `PRIVACY_DEV_PORT` | port number | `8001` | Used in development mode only to expose the privacy container's HTTP port to the host. |

Changes to `PRIVACY_LANGS` made through Actions → Install Options apply on save (a running privacy container is restarted automatically). If you edit the env file directly, restart Monadic Chat so the new value takes effect. After changing `PRIVACY_FILTER`, restart Monadic Chat (no rebuild required).
