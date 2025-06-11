# frozen_string_literal: true

require_relative 'json_handler'

module MonadicChat
  # HTML rendering for monadic structures
  module HtmlRenderer
    include JsonHandler
    
    # Render monadic structure as HTML (compatible with existing monadic_html)
    def render_as_html(monad, settings = {})
      obj = unwrap_from_json(monad)
      json_to_html(obj, settings)
    end
    
    # Convert JSON to HTML (matching existing json2html implementation)
    def json_to_html(hash, settings = {})
      options = {
        iteration: settings[:iteration] || 0,
        exclude_empty: settings[:exclude_empty] || true,
        mathjax: settings[:mathjax] || false
      }
      
      render_json_as_html(hash, options)
    end
    
    private
    
    # Core HTML rendering logic
    def render_json_as_html(hash, options)
      return hash.to_s unless hash.is_a?(Hash)
      
      iteration = options[:iteration] + 1
      output = +""
      
      # Handle message first if present
      if hash.key?("message")
        message = hash["message"]
        output += render_markdown(message, options[:mathjax])
        output += "<hr />"
        hash = hash.reject { |k, _| k == "message" }
      end
      
      # Render remaining fields
      hash.each do |key, value|
        display_key = snake_to_capitalized(key)
        data_key = key.downcase
        
        output += render_field(key, value, display_key, data_key, iteration, options)
      end
      
      output
    end
    
    # Render individual field based on type
    def render_field(key, value, display_key, data_key, iteration, options)
      # Handle empty values
      if value.nil? || (value.is_a?(String) && value.empty?) || (value.is_a?(Array) && value.empty?)
        return render_empty_field(display_key, data_key, iteration)
      end
      
      # Special handling for context
      if key.downcase == "context"
        return render_context_field(value, iteration, options)
      end
      
      # Render based on value type
      case value
      when Hash
        render_hash_field(display_key, value, data_key, iteration, options)
      when Array
        render_array_field(display_key, value, data_key, iteration, options)
      else
        render_simple_field(display_key, value, data_key, iteration, options)
      end
    end
    
    # Render empty field
    def render_empty_field(display_key, data_key, iteration)
      <<~HTML
        <div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>
          <span>#{display_key}: </span>
          <span>no value</span>
        </div>
      HTML
    end
    
    # Render context field with collapsible wrapper
    def render_context_field(value, iteration, options)
      <<~HTML
        <div class='json-item context' data-depth='#{iteration}' data-key='context'>
          <div class='json-header' onclick='toggleItem(this)'>
            <span>Context</span>
            <i class='fas fa-chevron-down float-right'></i> 
            <span class='toggle-text'>click to toggle</span>
          </div>
          <div class='json-content'>
            #{render_json_as_html(value, options.merge(iteration: iteration))}
          </div>
        </div>
      HTML
    end
    
    # Render hash field
    def render_hash_field(display_key, value, data_key, iteration, options)
      <<~HTML
        <div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>
          <div class='json-header' onclick='toggleItem(this)'>
            <span>#{display_key}</span>
            <i class='fas fa-chevron-down float-right'></i> 
            <span class='toggle-text'>click to toggle</span>
          </div>
          <div class='json-content'>
            #{render_json_as_html(value, options.merge(iteration: iteration))}
          </div>
        </div>
      HTML
    end
    
    # Render array field
    def render_array_field(display_key, value, data_key, iteration, options)
      if value.all? { |v| v.is_a?(String) }
        # Simple string array
        <<~HTML
          <div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>
            <span>#{display_key}: [#{value.join(', ')}]</span>
          </div>
        HTML
      else
        # Complex array
        items = value.map do |v|
          if v.is_a?(String)
            "<li>#{render_markdown(v, options[:mathjax])}</li>"
          else
            "<li>#{render_json_as_html(v, options.merge(iteration: iteration))}</li>"
          end
        end.join("\n")
        
        <<~HTML
          <div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>
            <div class='json-header' onclick='toggleItem(this)'>
              <span>#{display_key}</span>
              <i class='fas fa-chevron-down float-right'></i> 
              <span class='toggle-text'>click to toggle</span>
            </div>
            <div class='json-content'>
              <ul class='no-bullets'>
                #{items}
              </ul>
            </div>
          </div>
        HTML
      end
    end
    
    # Render simple field
    def render_simple_field(display_key, value, data_key, iteration, options)
      if value.is_a?(String) && !value.include?("\n")
        # Single line string
        <<~HTML
          <div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>
            <span>#{display_key}: </span>
            <span>#{value}</span>
          </div>
        HTML
      else
        # Multi-line or other content
        <<~HTML
          <div class='json-item' data-depth='#{iteration}' data-key='#{data_key}'>
            <span>#{display_key}: </span>
            <span>#{render_markdown(value.to_s, options[:mathjax])}</span>
          </div>
        HTML
      end
    end
    
    # Convert snake_case to Capitalized Words
    def snake_to_capitalized(snake_str)
      snake_str.to_s.split("_").map(&:capitalize).join(" ")
    rescue StandardError
      snake_str.to_s
    end
    
    # Render markdown content
    def render_markdown(content, mathjax = false)
      # Use StringUtils if available, otherwise basic escaping
      if defined?(StringUtils)
        StringUtils.markdown_to_html(content, mathjax: mathjax)
      else
        content.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\n", "<br>")
      end
    end
  end
end