# Testing Your Apps

This guide shows you how to test your custom Monadic Chat applications.

## Quick Start

### Testing Your App Manually

1. **Install your app** in `~/monadic/data/apps/`
2. **Restart Monadic Chat** to load your app
3. **Open the Console Panel** and select your app
4. **Test each feature** systematically:
   - Try basic conversations
   - Test all tools you've defined
   - Check error handling
   - Verify with different providers

### Writing Test Scripts

Create test scripts in `~/monadic/data/scripts/` to automate testing:

```ruby
# test_my_app.rb
require 'net/http'
require 'json'

# Test your app's functionality
puts "Testing MyApp..."

# Example: Test API endpoint
uri = URI('http://localhost:4567/api/your_endpoint')
response = Net::HTTP.get(uri)
puts "Response: #{response}"
```

## Testing Checklist

### Before Release
- [ ] App loads without errors
- [ ] All tools work as expected
- [ ] System prompt is clear and complete
- [ ] Works with multiple providers
- [ ] Handles errors gracefully
- [ ] Description and icon are appropriate

### Common Issues to Test

1. **Tool Execution**
   - Do tools get called when expected?
   - Are parameters passed correctly?
   - Does error handling work?

2. **Provider Compatibility**
   - Test with at least 2-3 different providers
   - Check that features degrade gracefully
   - Verify model-specific behaviors

3. **File Handling**
   - Test file uploads if your app uses them
   - Verify file paths are correct
   - Check file size limits

4. **Context Management**
   - For monadic apps, verify context updates
   - Check context size limits
   - Test context persistence

## Debugging Tips

### Enable Logging
1. Go to Console Panel Settings
2. Enable "Extra Logging"
3. Watch the console for detailed output

### Check Ruby Console
Look for errors in the console output:
- Syntax errors in your MDSL file
- Missing tool definitions
- Runtime exceptions

### Use Print Statements
Add debugging output to your Ruby code:
```ruby
def my_tool(param:)
  puts "DEBUG: my_tool called with param: #{param}"
  # Your tool logic here
end
```

## Performance Testing

### Response Time
- Measure how long tools take to execute
- Check for unnecessary API calls
- Optimize slow operations

### Memory Usage
- Monitor container memory usage
- Check for memory leaks in long conversations
- Test with large context sizes

## Integration Testing

If your app uses external services:

1. **Mock External APIs** during development
2. **Test with Real APIs** before release
3. **Handle API Failures** gracefully
4. **Respect Rate Limits**

## Example Test Scenarios

### Chat App Test
```
1. Start conversation with greeting
2. Ask follow-up questions
3. Test context retention
4. Try edge cases (empty input, very long input)
5. Test with different models
```

### Tool-Based App Test
```
1. Trigger each tool individually
2. Test tool combinations
3. Provide invalid parameters
4. Test error recovery
5. Verify output format
```

## Getting Help

- Check existing apps for testing patterns
- Use Monadic Help app for guidance
- Review console logs for errors
- Test incrementally as you develop

## Best Practices

1. **Test Early and Often** - Don't wait until your app is complete
2. **Document Test Cases** - Keep notes on what you've tested
3. **Use Version Control** - Save working versions before changes
4. **Get User Feedback** - Have others test your app
5. **Test Edge Cases** - Try unusual inputs and scenarios