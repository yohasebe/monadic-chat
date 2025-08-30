#!/usr/bin/env ruby
# Clear Cohere models cache to force refresh with deprecated:false models

# Clear the global cache
$MODELS ||= {}
$MODELS[:cohere] = nil

puts "Cohere models cache cleared. Restart the server to see changes."
puts ""
puts "Expected models to appear in Web UI:"
puts "  - command-a-03-2025"
puts "  - command-a-translate-08-2025"
puts ""
puts "These models have deprecated:false in model_spec.js and will be"
puts "added to the dropdown even though they're not in the Cohere API list."