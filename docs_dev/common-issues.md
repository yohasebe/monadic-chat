# Common Development Issues & Solutions

## Build Issues

### Electron packaging fails
```bash
# Clear npm cache
npm cache clean --force
rm -rf node_modules package-lock.json
npm install

# For notarization issues on Mac
export APPLE_ID="your-apple-id"
export APPLE_APP_SPECIFIC_PASSWORD="your-app-password"
```

### Docker build errors
```bash
# Complete cleanup (WARNING: removes unused images)
docker system prune -a --volumes

# Rebuild via compose
docker compose --project-directory docker/services -f docker/services/compose.yml down
docker compose --project-directory docker/services -f docker/services/compose.yml build --no-cache
docker compose --project-directory docker/services -f docker/services/compose.yml up -d
```

## Runtime Issues

### "Cannot find module" errors after reorganization
- Check `app.isPackaged` conditionals in app/main.js
- Verify paths in process.resourcesPath vs __dirname
- Run `scripts/fix_packaged_paths.sh` if needed

### API tests failing with provider-specific errors
- Prefer mdsl/model_spec defaults. Avoid forcing params (e.g., temperature) that a model may not support.
- Scope providers explicitly when isolating issues:
```bash
# Run only selected providers
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke

# Exclude local backends (e.g., Ollama) by omission
RUN_API=true PROVIDERS=openai,gemini rake spec_api:all
```
- Enable request logging to diagnose:
```bash
API_LOG=true RUN_API=true rake spec_api:smoke
```

### WebSocket connection issues
1. Check Ruby server is running: `ps aux | grep thin`
2. Verify port 4567 is accessible: `curl localhost:4567/health`
3. Check browser console for CORS errors
4. Restart server: `rake server:restart`

## Development Tips

### Fast iteration on Ruby code
```bash
# Use debug mode to skip Ruby container
rake server:debug

# Watch logs
tail -f ~/monadic/log/server.log
```

### Testing specific providers
```bash
# Test only specific providers
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke

# Skip media tests for speed
RUN_API=true RUN_MEDIA=false rake spec_api:all
```

### Debugging Electron paths
```javascript
// Add to app/main.js temporarily
console.log('isPackaged:', app.isPackaged);
console.log('resourcesPath:', process.resourcesPath);
console.log('__dirname:', __dirname);
console.log('computed path:', computedPath);
```

## Performance Issues

### Slow container startup
- Increase Docker memory allocation (Docker Desktop → Settings)
- Use `rake server:debug` for development
- Disable unused containers in docker/compose.yml

### Test suite taking too long
```bash
# Run quick smoke tests only
RUN_API=true rake spec_api:quick

# Use SUMMARY_ONLY for cleaner output
SUMMARY_ONLY=1 rake spec_api:smoke
```
