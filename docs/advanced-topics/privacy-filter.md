# Privacy Filter (PII Masking)

## Overview

The Privacy Filter masks personally identifiable information (PII) in user messages before they are sent to AI providers, then restores the original values in the AI's response on the way back. Detection runs locally in a separate Docker container (Microsoft Presidio + spaCy) so PII never leaves your machine on its way to or from the LLM.

The feature is opt-in and disabled by default. It does not affect existing apps or sessions until you both install the container and turn the per-session toggle on.

## When to Use It

- Drafting emails or documents that mention real names, email addresses, or phone numbers.
- Translating text that contains personal information.
- Sharing snippets that include sensitive identifiers without rewriting them by hand.

## Installation

The Privacy Filter requires a separate Docker container. The English baseline image is around 1 GB; each additional language adds 150-300 MB.

1. Open **Settings → Install Options**.
2. Locate the **Privacy Filter (PII Masking)** section.
3. Check **Install Privacy Filter (English baseline)**.
4. Optionally check any of the additional languages: Japanese, German, Spanish, French, Italian, Dutch, Portuguese, Chinese.
5. Click **Save**.
6. Switch to **Settings → Actions** and click **Build Privacy** (or use the menu: **Actions → Build Privacy Container**). The button is enabled only when the master checkbox is on and Docker is in the Stopped state.
7. Wait for the build to finish. The console panel shows progress and a final "Build of Privacy container has finished" message.

To uninstall, uncheck the master checkbox and Save. The feature is disabled at runtime; the image can be removed manually with `docker rmi yohasebe/monadic-privacy`.

## Per-Session Toggle

Once the container is installed, apps that support privacy filtering show a **Privacy Filter** toggle in the Session Controls panel. The toggle is unchecked at the start of every session.

- Turn it on before sending the first message to enable masking for the session.
- After the first message is sent the toggle locks. Pressing **Reset** or switching to a different app re-enables editing.
- Your last choice is remembered per app, so switching back to an app restores its previous toggle state.

When the toggle is disabled, hovering over it shows the reason:

- *This app does not support Privacy Filter.* — The app's MDSL does not declare a `privacy` block.
- *Privacy Filter is not installed. Open Settings → Install Options to enable it.* — `PRIVACY_FILTER=true` is not set in the environment, or the container has not been built yet.

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
- Masking adds a small per-message latency, typically 50-200 ms depending on text length and the languages enabled.
- Coverage and accuracy vary by language because each spaCy model is trained on a different corpus. English has the most thorough validation; other languages are added as additional spaCy models with default Presidio recognizers.

## Configuration Reference

Settings stored in `~/monadic/config/env`:

| Variable | Values | Default | Description |
|---|---|---|---|
| `PRIVACY_FILTER` | `true` / `false` | `false` | Master gate. Must be `true` to build and use the privacy container. |
| `PRIVACY_LANGS` | comma-separated language codes | `en` | spaCy language models to install (e.g. `en,ja,de`). English is always included. |
| `PRIVACY_DEV_PORT` | port number | `8001` | Used in development mode only to expose the privacy container's HTTP port to the host. |

After changing `PRIVACY_FILTER` or `PRIVACY_LANGS`, rebuild the container (Settings → Actions → Build Privacy) and restart Monadic Chat so the new environment values take effect.
