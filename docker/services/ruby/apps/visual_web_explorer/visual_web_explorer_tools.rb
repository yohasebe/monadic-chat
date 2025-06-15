module VisualWebExplorerTools
  
  # Track screenshots for the current session
  def initialize_session
    @captured_screenshots = []
  end
  
  def capture_viewport_screenshots(url:, viewport_width: nil, viewport_height: nil, overlap: nil, preset: nil)
    # Validate URL
    unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
      return { success: false, error: "Invalid URL format. Please provide a valid HTTP or HTTPS URL." }
    end
    
    # Build command
    cmd_parts = ["viewport_capturer.py", url]
    
    # Apply preset or custom dimensions
    if preset
      cmd_parts << "--preset #{preset}"
    else
      cmd_parts << "-w #{viewport_width}" if viewport_width
      cmd_parts << "--height #{viewport_height}" if viewport_height
    end
    
    cmd_parts << "--overlap #{overlap}" if overlap
    
    command = "python $(which " + cmd_parts[0] + ") " + cmd_parts[1..-1].join(" ")
    
    # Execute capture
    output = send_command(command: command, container: "python")
    
    # Check if the command succeeded by looking for SUCCESS or ERROR in output
    if output.include?("SUCCESS:")
      # Parse output to extract screenshot filenames
      output_lines = output.split("\n")
      screenshots = output_lines.select { |line| line.strip.start_with?("- ") }
                               .map { |line| line.strip[2..-1] }
      
      # Store in session
      @captured_screenshots ||= []
      @captured_screenshots.concat(screenshots)
      
      # Create image gallery HTML
      gallery_html = create_screenshot_gallery(screenshots)
      
      {
        success: true,
        message: "Successfully captured #{screenshots.length} screenshots.",
        screenshots: screenshots,
        filenames: screenshots.join("\n"),
        gallery_html: gallery_html,
        display_instruction: "Display the images using the gallery_html provided."
      }
    elsif output.include?("ERROR:")
      {
        success: false,
        error: output
      }
    else
      {
        success: false,
        error: "Unexpected output: #{output}"
      }
    end
  end
  
  def list_captured_screenshots
    @captured_screenshots ||= []
    
    if @captured_screenshots.empty?
      {
        success: true,
        message: "No screenshots have been captured in this session yet.",
        screenshots: []
      }
    else
      gallery_html = create_screenshot_gallery(@captured_screenshots)
      {
        success: true,
        message: "Found #{@captured_screenshots.length} screenshots in this session",
        screenshots: @captured_screenshots,
        gallery_html: gallery_html,
        display_instruction: "Please display the gallery_html below to show all captured screenshots."
      }
    end
  end
  
  def get_viewport_presets
    presets = {
      desktop: {
        width: 1920,
        height: 1080,
        description: "Standard desktop/laptop screen"
      },
      tablet: {
        width: 1024,
        height: 768,
        description: "iPad landscape orientation"
      },
      mobile: {
        width: 375,
        height: 812,
        description: "iPhone X/11/12 dimensions"
      },
      print: {
        width: 794,
        height: 1123,
        description: "A4 paper size at 96 DPI"
      }
    }
    
    {
      success: true,
      presets: presets,
      message: "Available viewport presets with their dimensions"
    }
  end
  
  def capture_webpage_text(url:, use_image_recognition: false)
    # Validate URL
    unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
      return { success: false, error: "Invalid URL format. Please provide a valid HTTP or HTTPS URL." }
    end
    
    if use_image_recognition
      # First capture screenshots, then use image recognition
      result = capture_viewport_screenshots(url: url, preset: "desktop")
      
      if result[:success] && result[:screenshots] && !result[:screenshots].empty?
        # Use provider-specific image recognition
        first_screenshot = result[:screenshots].first
        # Use the correct path based on environment
        # IN_CONTAINER is a constant defined in lib/monadic.rb
        image_path = if defined?(IN_CONTAINER) && IN_CONTAINER
                       "/monadic/data/#{first_screenshot}"
                     else
                       File.join(Dir.home, "monadic", "data", first_screenshot)
                     end
        
        analysis_prompt = "Extract all text content from this webpage screenshot. Format the output as clean Markdown with proper headings, lists, and paragraphs. Include all visible text but exclude navigation elements and advertisements if possible."
        
        begin
          # Check if file exists with fallback
          unless File.exist?(image_path)
            # Try alternative path if first path fails
            alternative_path = if defined?(IN_CONTAINER) && IN_CONTAINER
                                File.join(Dir.home, "monadic", "data", first_screenshot)
                              else
                                "/monadic/data/#{first_screenshot}"
                              end
            
            if File.exist?(alternative_path)
              image_path = alternative_path
            else
              # If still not found, provide detailed error
              return {
                success: false,
                error: "Screenshot file not found. Tried paths: #{image_path} and #{alternative_path}. Environment: #{defined?(IN_CONTAINER) ? (IN_CONTAINER ? 'container' : 'local') : 'unknown'}"
              }
            end
          end
          
          # Read the image and encode it
          image_data = File.read(image_path)
          base64_image = Base64.strict_encode64(image_data)
          mime_type = case File.extname(image_path).downcase
                      when '.jpg', '.jpeg' then 'image/jpeg'
                      when '.png' then 'image/png'
                      when '.gif' then 'image/gif'
                      else 'image/png'
                      end
          
          # Prepare the message with image
          provider = @settings["provider"] || "openai"
          
          case provider
          when "claude"
            # Use Claude's native image format
            messages = [{
              "role" => "user",
              "content" => [
                {"type" => "text", "text" => analysis_prompt},
                {
                  "type" => "image",
                  "source" => {
                    "type" => "base64",
                    "media_type" => mime_type,
                    "data" => base64_image
                  }
                }
              ]
            }]
          when "gemini"
            # Use Gemini's inline data format
            messages = [{
              "role" => "user",
              "parts" => [
                {"text" => analysis_prompt},
                {
                  "inlineData" => {
                    "mimeType" => mime_type,
                    "data" => base64_image
                  }
                }
              ]
            }]
          when "grok"
            # Use Grok's OpenAI-compatible format
            messages = [{
              "role" => "user",
              "content" => [
                {"type" => "text", "text" => analysis_prompt},
                {
                  "type" => "image_url",
                  "image_url" => {
                    "url" => "data:#{mime_type};base64,#{base64_image}",
                    "detail" => "high"
                  }
                }
              ]
            }]
          else
            # Default to OpenAI format or use analyze_image
            text_result = analyze_image(message: analysis_prompt, image_path: image_path)
            
            return {
              success: true,
              message: "Text extracted using image recognition",
              content: text_result,
              method: "image_recognition",
              screenshots: result[:screenshots],
              gallery_html: create_screenshot_gallery(result[:screenshots])
            }
          end
          
          # Make API request using the appropriate provider
          response = api_request(messages: messages, max_tokens: 4000)
          
          if response && response["content"]
            {
              success: true,
              message: "Text extracted using #{provider} image recognition",
              content: response["content"],
              method: "image_recognition_#{provider}",
              screenshots: result[:screenshots],
              gallery_html: create_screenshot_gallery(result[:screenshots])
            }
          else
            {
              success: false,
              error: "Image recognition failed - no response from #{provider}"
            }
          end
        rescue => e
          {
            success: false,
            error: "Image recognition failed: #{e.message}"
          }
        end
      else
        {
          success: false,
          error: "Failed to capture screenshots for image recognition"
        }
      end
    else
      # Use webpage_fetcher.py for direct text extraction
      command = "python $(which webpage_fetcher.py) --url \"#{url}\" --mode md --output stdout"
      output = send_command(command: command, container: "python")
      
      # Check if successful
      if output && !output.empty? && !output.include?("ERROR:")
        # The webpage_fetcher.py outputs content directly to stdout in markdown format
        content = output.strip
        
        # Remove any error messages that might be at the beginning
        if content.include?("Successfully saved") || content.include?("===")
          # Try to extract just the markdown content
          lines = content.split("\n")
          # Skip any status messages
          content_start = lines.find_index { |line| line.strip.start_with?("#") || line.strip.match?(/^[A-Za-z]/) }
          if content_start
            content = lines[content_start..-1].join("\n").strip
          end
        end
        
        # Check if content is meaningful
        if content.length < 100
          {
            success: true,
            message: "Text extraction returned minimal content. Consider using image recognition for better results.",
            content: content,
            method: "html_parsing",
            suggestion: "Try again with image recognition enabled for potentially better results."
          }
        else
          {
            success: true,
            message: "Successfully extracted text content",
            content: content,
            method: "html_parsing"
          }
        end
      else
        # Try with image recognition as fallback
        {
          success: false,
          error: "Text extraction failed. Try enabling image recognition mode.",
          suggestion: "The webpage might use dynamic content or have anti-scraping measures. Image recognition mode may work better."
        }
      end
    end
  end
  
  private
  
  def create_screenshot_gallery(screenshots)
    return "" if screenshots.empty?
    
    # Use Monadic Chat's standard image display format
    html = ""
    screenshots.each_with_index do |filename, index|
      html += <<~HTML
        <div class="generated_image">
          <p><strong>Screenshot #{index + 1}:</strong> #{filename}</p>
          <img src="/data/#{filename}" alt="Screenshot #{index + 1}" />
        </div>
      HTML
    end
    
    html
  end
end
