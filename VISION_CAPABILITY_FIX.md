# Vision Capability Fix Summary

## Problem
The `vision_capability` parameter from the model spec was not being properly passed from the client to the server, causing the OpenAI helper to always switch models when images were included, even for models that already have vision capability.

## Root Cause
In `/docker/services/ruby/public/js/monadic/utilities.js`, the `setParams()` function was trying to access an undefined variable `model` instead of using `params["model"]` when looking up the model spec.

## Solution

### 1. Fixed JavaScript Bug (utilities.js)
Changed line 743 from:
```javascript
const spec = modelSpec[model];
```
to:
```javascript
const spec = modelSpec[params["model"]];
```

This ensures that the `vision_capability` from the model spec is properly included in the parameters sent to the server.

### 2. Updated Vision-Capable Models List (openai_helper.rb)
Added missing vision-capable models to the hardcoded list:
- gpt-4.5
- gpt-4.5-preview
- gpt-4o
- gpt-4o-mini
- o3-pro

## How It Works Now

1. When a user selects a model, the client checks the model spec
2. If the model has `vision_capability: true`, this is included in the parameters
3. The server receives this parameter and checks both:
   - The hardcoded list of vision-capable models
   - The `vision_capability` parameter from the client
4. If either indicates the model has vision capability, no model switching occurs

## Benefits
- Models with vision capability (like o3-pro, gpt-4.5) no longer switch to gpt-4.1 when images are included
- Better performance and cost efficiency by using the intended model
- Consistent user experience without unexpected model switches

## Testing
To test the fix:
1. Select a vision-capable model (e.g., o3-pro, gpt-4.5-preview)
2. Upload an image and send a message
3. Verify that no "Model automatically switched" notification appears
4. The response should come from the originally selected model