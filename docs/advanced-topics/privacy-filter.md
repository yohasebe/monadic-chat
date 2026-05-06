# Privacy Filter (PII Masking)

## Overview

The Privacy Filter masks personally identifiable information (PII) in user messages before they are sent to AI providers, then restores the original values in the AI's response on the way back. Detection runs locally in a separate Docker container (Microsoft Presidio + spaCy) so PII never leaves your machine on its way to or from the LLM.

The Privacy container is part of Monadic Chat's default container set, so the feature is ready to use the first time you start the app. Each app's per-session toggle starts off and must be turned on to enable masking for that conversation.

## When to Use It

- Drafting emails or documents that mention real names, email addresses, or phone numbers.
- Translating text that contains personal information.
- Sharing snippets that include sensitive identifiers without rewriting them by hand.

## Installation

The Privacy container is built and started automatically with the rest of Monadic Chat. English is mandatory and always installed; the base image is around 1 GB.

To enable masking for non-English content, add additional spaCy NER models:

1. Open **Settings → Install Options**.
2. Locate the **Privacy Filter — Additional Languages** section.
3. Check the languages you want from German (de), Spanish (es), French (fr), Italian (it), Japanese (ja), Dutch (nl), Portuguese (pt), Chinese (zh). English is always present and cannot be unchecked.
4. Click **Save**. The Privacy section's status badge changes to **rebuild-needed**.
5. Switch to **Settings → Actions** and click **Build Privacy** (or use the menu: **Actions → Build Privacy Container**). The button is enabled when Docker is in the Stopped state.
6. Wait for the build to finish. Each additional language downloads a spaCy model (~50 MB each) and is baked into the container image.

Languages stay installed until you uncheck them and rebuild. Removing a language frees up space in the container image at the next build.

Runtime opt-out: set `PRIVACY_FILTER=false` in `~/monadic/config/env` to skip the Privacy container entirely. The toggle becomes disabled with the tooltip "Privacy Filter is disabled." until the env value is restored.

## Per-Session Toggle

Once the container is installed, apps that support privacy filtering show a **Privacy Filter** toggle in the Session Controls panel. The toggle is unchecked at the start of every session.

- Turn it on before sending the first message to enable masking for the session.
- After the first message is sent the toggle locks. Pressing **Reset** or switching to a different app re-enables editing.
- Your last choice is remembered per app, so switching back to an app restores its previous toggle state.

When the toggle is disabled, hovering over it shows the reason:

- *This app does not support Privacy Filter.* — The app's MDSL does not declare a `privacy` block.
- *Privacy Filter is disabled.* — `PRIVACY_FILTER=false` is set in the environment, so the Privacy container was not started.
- *Privacy Filter is not installed for this language. Install via Settings → Install Options.* — The sidebar's conversation_language is not among the Presidio languages currently baked into the container. Install the language and rebuild, or change the conversation_language to one that is installed.

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

Clicking the indicator opens the **Registry Viewer**, which lists each placeholder, the original value, and the entity type (PERSON, EMAIL_ADDRESS, and so on). The registry is held in session memory only; it is never written to the conversation log on disk.

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

## Knowledge Base Retrieval (`library_search`)

The Knowledge Base stores conversations and imported documents **unmasked** — the Save dialog warns you about this. When the Privacy Filter is active in a session that calls `library_search`, the retrieved snippets pass through the same Privacy Pipeline before they reach the LLM. Any PII present in the Knowledge Base is masked into placeholders for the request, and the LLM's reply is restored on the way back via the existing streaming-handler pass.

This closes a back-channel that would otherwise let saved PII reach the LLM via retrieval, even though the user enabled the Privacy Filter for the current session. The masking is best-effort — if the pipeline raises, the tool falls back to the raw snippet rather than failing the search.

## Encrypted Export

When the Privacy Filter has masked at least one entity in the current session, the **Save** button opens a unified export dialog with two orthogonal axes:

- **Encryption**: encrypt the file with AES-256-GCM (Argon2id key derivation) using a passphrase you provide.
- **Content**: export the conversation either with original values restored or with placeholders kept in place.

Three combinations are commonly useful:

1. **Encrypted + Restored** — a personal archive that can only be opened by you.
2. **Encrypted + Masked** — share analysis logs without exposing PII even after decryption.
3. **Plain + Masked** — quick sharable example with no real names.

Passphrase requirements: minimum 8 characters and the confirmation field must match. The strength meter is informational only and does not block submission.

To re-open an encrypted export, use the **Load** button and enter the passphrase when prompted. The registry is restored alongside the conversation so subsequent messages continue to mask consistently.

## Supported Apps

The Privacy Filter is enabled in the MDSL definitions of these apps:

- Mail Composer
- Chat Plus
- Translate
- Second Opinion
- Chat

Other apps do not declare `privacy do` and the toggle stays disabled. Apps that primarily generate code, media, or speech were excluded because masking would interfere with their core output (placeholders inside generated code, for example, would not be useful).

## Limitations

- Assistant-side history is not re-masked. The pipeline applies to the user role on each turn; if the assistant repeats a name in a later turn, that occurrence passes through unchanged.
- Custom recognizers live in the privacy container source (`docker/services/privacy/recognizers/`). Adding new recognizers requires rebuilding the container.
- Masking adds a small per-message latency, typically 50-200 ms depending on text length.
- Supported masking languages are limited to the nine spaCy NER models bundled with Presidio: English, German, Spanish, French, Italian, Japanese, Dutch, Portuguese, Chinese. Languages outside this set (e.g. Korean, Arabic) cannot use the Privacy Filter — the session toggle is disabled when the sidebar conversation_language is one of them.

## Configuration Reference

Settings stored in `~/monadic/config/env`:

| Variable | Values | Default | Description |
|---|---|---|---|
| `PRIVACY_FILTER` | `true` / `false` | `true` | Runtime gate. Set to `false` to skip starting the privacy container at startup; the toggle becomes disabled until restored to `true`. |
| `PRIVACY_LANGS` | comma-separated language codes | `en` | spaCy NER models baked into the privacy container at build time. English is mandatory and prepended automatically. The preferred edit path is Settings → Install Options → "Privacy Filter — Additional Languages"; advanced users can edit the env file directly. Supported codes: `en`, `de`, `es`, `fr`, `it`, `ja`, `nl`, `pt`, `zh`. |
| `PRIVACY_DEV_PORT` | port number | `8001` | Used in development mode only to expose the privacy container's HTTP port to the host. |

After changing `PRIVACY_LANGS`, rebuild the container (Settings → Actions → Build Privacy) and restart Monadic Chat so the new language models take effect. After changing `PRIVACY_FILTER`, restart Monadic Chat (no rebuild required).
