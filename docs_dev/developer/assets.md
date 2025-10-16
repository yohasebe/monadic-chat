# CDN Assets Management for Developers

## Overview

Monadic Chat provides CDN asset management scripts to download third-party libraries for offline use in both local development and Docker builds.

## Files

- `/docker/services/ruby/bin/assets_list.sh`: Central configuration file defining all required assets
- `/bin/assets.sh`: Script to download assets for local development
- `/docker/services/ruby/scripts/download_assets.sh`: Script used during Docker builds

## How to Add New Assets

When you need to add a new library or asset:

1. Add an entry to the `ASSETS` array in `/docker/services/ruby/bin/assets_list.sh`:
   ```
   "type,url,filename"
   ```

   Where:
   - `type`: Asset type (css, js, font, webfont, mathfont)
   - `url`: Full URL to the asset on CDN
   - `filename`: Local filename to save as

   Example:
   ```bash
   "js,https://cdn.example.com/library.min.js,library.min.js"
   ```

2. No other changes are needed - all scripts use the same asset list.

## Asset Types and Storage

Assets are organized by type:
- **CSS**: Stored in `vendor/css/`
- **JS**: Stored in `vendor/js/`
- **Fonts**: Stored in `vendor/fonts/` (for regular fonts like Montserrat)
- **Webfonts**: Stored in `vendor/webfonts/` (for icon fonts like Font Awesome)
- **Math fonts**: Stored in `vendor/js/output/chtml/fonts/woff-v2/` (for MathJax)

## Usage

Run locally:
```bash
rake download_vendor_assets
```

This is automatically run during the build process when packaging the application.

## Docker Integration

Assets are downloaded during Docker build:
- Automatically executed at build time (Dockerfile line 96)
- Downloads to `/monadic/public/vendor/` in the container
- Skips files that already exist
- Includes special processing for Font Awesome CSS paths (converts relative paths to absolute)
- Platform-specific sed commands handle macOS vs Linux differences

## Current Assets

The system includes:
- **CSS frameworks**: Bootstrap, jQuery UI
- **JavaScript libraries**: jQuery, MathJax, Mermaid, ABC.js
- **Icon fonts**: Font Awesome
- **Web fonts**: Montserrat family
- **Media libraries**: Opus Media Recorder for audio recording