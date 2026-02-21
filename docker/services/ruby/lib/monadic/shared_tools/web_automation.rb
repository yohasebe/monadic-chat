# frozen_string_literal: true

module MonadicSharedTools
  module WebAutomation
    include MonadicHelper
    include Monadic::Utils::SeleniumHelper

    # Cache for container availability check (reduces docker ps calls)
    @availability_cache ||= { ts: Time.at(0), available: false }

    # Check if Selenium and Python containers are available
    # Results are cached for 10 seconds to reduce docker ps overhead
    def self.available?
      # Return cached result if still valid (10 second TTL)
      if (Time.now - @availability_cache[:ts]) <= 10
        return @availability_cache[:available]
      end

      # Perform actual check
      containers = `docker ps --format "{{.Names}}"`
      selenium_available = containers.include?("monadic-chat-selenium-container") || containers.include?("monadic_selenium")
      python_available = containers.include?("monadic-chat-python-container") || containers.include?("monadic_python")
      available = selenium_available && python_available

      # Update cache
      @availability_cache = { ts: Time.now, available: available }

      available
    end

    TOOLS = [
      {
        type: "function",
        function: {
          name: "capture_viewport_screenshots",
          description: "Capture a web page as multiple viewport-sized screenshots",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "The URL of the web page to capture"
              },
              viewport_width: {
                type: "integer",
                description: "Width of the viewport in pixels (default: 1920)"
              },
              viewport_height: {
                type: "integer",
                description: "Height of the viewport in pixels (default: 1080)"
              },
              overlap: {
                type: "integer",
                description: "Number of pixels to overlap between screenshots (default: 100)"
              },
              preset: {
                type: "string",
                description: "Use preset viewport sizes: desktop, tablet, mobile, or print"
              }
            },
            required: ["url"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "list_captured_screenshots",
          description: "List all screenshots captured in the current session",
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        }
      },
      {
        type: "function",
        function: {
          name: "get_viewport_presets",
          description: "Get available viewport preset dimensions",
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        }
      },
      {
        type: "function",
        function: {
          name: "capture_webpage_text",
          description: "Extract text content from a web page by capturing screenshots and using image recognition to read them. Works reliably with modern JavaScript-heavy sites, SPAs, and dynamically rendered content.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "The URL of the web page to extract text from"
              }
            },
            required: ["url"]
          }
        }
      }
    ].freeze

    def self.tools
      TOOLS
    end

    # Track screenshots for the current session
    def initialize_session
      @captured_screenshots = []
    end

    def capture_viewport_screenshots(url:, viewport_width: nil, viewport_height: nil, overlap: nil, preset: nil)
      # Check if Selenium is available
      if error = check_selenium_or_error
        return error
      end

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

      command = cmd_parts.join(" ")

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

    def capture_webpage_text(url:)
      # Check if Selenium is available
      if error = check_selenium_or_error
        return error
      end

      # Validate URL
      unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
        return { success: false, error: "Invalid URL format. Please provide a valid HTTP or HTTPS URL." }
      end

      # Capture screenshots of the full page
      result = capture_viewport_screenshots(url: url, preset: "desktop")

      unless result[:success] && result[:screenshots] && !result[:screenshots].empty?
        return {
          success: false,
          error: "Failed to capture screenshots of the page."
        }
      end

      screenshots = result[:screenshots]
      analysis_prompt = "Extract all text content from this webpage screenshot. Format the output as clean Markdown with proper headings, lists, and paragraphs. Include all visible text but exclude navigation elements and advertisements if possible."

      # Process each screenshot with image recognition and collect results
      extracted_parts = []
      errors = []

      screenshots.each_with_index do |filename, index|
        image_path = File.join(Monadic::Utils::Environment.data_path, filename)

        # Validate image path
        unless validate_file_path(image_path)
          errors << "Invalid path for screenshot #{index + 1}: #{filename}"
          next
        end

        unless File.exist?(image_path)
          errors << "Screenshot file not found: #{filename}"
          next
        end

        begin
          text_result = analyze_image(message: analysis_prompt, image_path: image_path)
          if text_result && !text_result.strip.empty?
            extracted_parts << text_result.strip
          end
        rescue => e
          errors << "Image recognition failed for screenshot #{index + 1}: #{e.message}"
        end
      end

      if extracted_parts.empty?
        return {
          success: false,
          error: "Image recognition returned no text from #{screenshots.length} screenshots.",
          details: errors.empty? ? nil : errors
        }
      end

      # Combine text from all screenshots
      combined_content = extracted_parts.join("\n\n---\n\n")

      {
        success: true,
        message: "Text extracted from #{extracted_parts.length}/#{screenshots.length} screenshots using image recognition.",
        content: combined_content,
        method: "image_recognition",
        screenshots: screenshots,
        gallery_html: create_screenshot_gallery(screenshots),
        errors: errors.empty? ? nil : errors
      }
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
end
