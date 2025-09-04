# External JavaScript Library Management System

## Overview
Monadic Chat uses a centralized system for managing external JavaScript and CSS libraries. This ensures consistency between development and production builds, and allows offline usage of all vendor assets.

## System Components

### 1. Configuration File
**Location**: `docker/services/ruby/bin/assets_list.sh`

This bash script contains an array of all external libraries to be downloaded. Format:
```bash
ASSETS=(
  "type,url,filename"
)
```

Where:
- `type`: Asset type (`css`, `js`, `font`, `webfont`, `mathfont`)
- `url`: Full CDN URL to the asset
- `filename`: Local filename to save as

### 2. Download Script
**Location**: `bin/assets.sh`

This script reads the configuration and downloads all assets to the appropriate vendor directories:
- CSS → `docker/services/ruby/public/vendor/css/`
- JS → `docker/services/ruby/public/vendor/js/`
- Fonts → `docker/services/ruby/public/vendor/fonts/`
- Web Fonts → `docker/services/ruby/public/vendor/webfonts/`
- Math Fonts → `docker/services/ruby/public/vendor/js/output/chtml/fonts/woff-v2/`

### 3. Rake Task
**Command**: `rake download_vendor_assets`

Convenience task that runs the download script.

## Adding a New Library

### Step 1: Add to Configuration
Edit `docker/services/ruby/bin/assets_list.sh`:

```bash
ASSETS=(
  # ... existing entries ...
  "js,https://cdn.example.com/library.min.js,library.min.js"
)
```

### Step 2: Download Assets
```bash
rake download_vendor_assets
```

### Step 3: Add to HTML Template
Edit `docker/services/ruby/views/index.erb`:

```html
<!-- Library Name (local or CDN fallback) -->
<script src="vendor/js/library.min.js" 
        onerror="this.onerror=null;this.src='https://cdn.example.com/library.min.js';"></script>
```

The `onerror` attribute provides CDN fallback if the local file fails to load.

### Step 4: Add Helper Scripts (Optional)
If the library needs initialization or helper functions, create:
`docker/services/ruby/public/js/monadic/library_helper.js`

## Current Libraries

### Core Libraries
- **Bootstrap 5.3.3**: UI framework
- **jQuery 3.7.0**: DOM manipulation
- **jQuery UI 1.14.1**: UI components
- **Font Awesome 6.7.2**: Icons

### Specialized Libraries
- **MathJax 3.2.2**: Mathematical notation
- **Mermaid 11.4.1**: Diagram generation
- **ABC.js 6.4.4**: ABC music notation
- **VexFlow 4.2.5**: Music notation rendering
- **Tone.js 14.8.49**: Web Audio synthesis

### Media Libraries
- **Opus Media Recorder**: Audio recording
- **Lame.js**: MP3 encoding

## Best Practices

1. **Version Pinning**: Always use specific versions in CDN URLs (not `@latest`)
2. **Minified Files**: Use `.min.js` and `.min.css` versions
3. **CDN Fallback**: Always include `onerror` fallback in HTML
4. **Local Testing**: Test with `rake download_vendor_assets` before committing
5. **Documentation**: Update this file when adding new libraries

## Build Integration

Downloaded vendor assets are automatically included in:
- Development server (`rake server:start`)
- Production builds (Electron packaging)
- Docker images

## Troubleshooting

### Assets Not Loading
1. Check if file exists in vendor directory
2. Verify URL in `assets_list.sh` is correct
3. Run `rake download_vendor_assets` to re-download
4. Check browser console for 404 errors

### CDN Fallback Not Working
1. Verify `onerror` syntax in index.erb
2. Check if CDN URL is still valid
3. Test with browser DevTools network throttling

### File Already Exists
The download script skips existing files. To force re-download:
```bash
rm docker/services/ruby/public/vendor/js/library.min.js
rake download_vendor_assets
```

## Related Files
- `docker/services/ruby/bin/assets_list.sh` - Asset configuration
- `bin/assets.sh` - Download script
- `docker/services/ruby/views/index.erb` - HTML template
- `Rakefile` - Rake task definition

## Security Considerations
- Always use HTTPS URLs for CDN resources
- Verify integrity of downloaded files when possible
- Consider using SRI (Subresource Integrity) hashes for critical libraries
- Regularly update libraries for security patches