# CDN Assets Management

## Overview

These scripts handle downloading third-party libraries from CDNs for local use in the application.

## Files

- `/docker/services/ruby/bin/assets_list.sh`: Central configuration file defining all required assets
- `download_vendor_assets.sh`: Script to download assets for local development

## How to Add New Assets

When you need to add a new library or asset:

1. Add an entry to the `ASSETS` array in `/docker/services/ruby/bin/assets_list.sh`:
   ```
   "type,url,filename"
   ```

   Where:
   - `type`: Asset type (css, js, font, webfont)
   - `url`: Full URL to the asset
   - `filename`: Local filename to save as

   Example:
   ```bash
   "js,https://cdn.example.com/library.min.js,library.min.js"
   ```

2. No other changes are needed - both scripts use the same asset list.

## Usage

Run locally:
```bash
rake download_vendor_assets
```

This is automatically run during the build process when packaging the application.

## Docker Integration

Assets are downloaded during Docker build. The Docker version of the script will look for the assets list or create its own copy if necessary.