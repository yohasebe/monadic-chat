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
    ].freeze

    INTERACTIVE_TOOLS = [
      {
        type: "function",
        function: {
          name: "start_browser",
          description: "Start an interactive browser session (non-headless) and navigate to a URL. The browser is visible via noVNC at http://localhost:7900 so users can watch in real time.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "The URL to open in the browser"
              }
            },
            required: ["url"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_navigate",
          description: "Navigate the interactive browser to a new URL within the existing session.",
          parameters: {
            type: "object",
            properties: {
              url: {
                type: "string",
                description: "The URL to navigate to"
              }
            },
            required: ["url"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_click",
          description: "Click an element on the page identified by a CSS selector.",
          parameters: {
            type: "object",
            properties: {
              selector: {
                type: "string",
                description: "CSS selector of the element to click (e.g., '#submit-btn', '.nav-link', 'button:nth-of-type(2)')"
              },
              description: {
                type: "string",
                description: "Brief description of what is being clicked (for user context)"
              }
            },
            required: ["selector"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_type",
          description: "Type text into an input field identified by a CSS selector.",
          parameters: {
            type: "object",
            properties: {
              selector: {
                type: "string",
                description: "CSS selector of the input element"
              },
              text: {
                type: "string",
                description: "Text to type into the element"
              }
            },
            required: ["selector", "text"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_screenshot",
          description: "Take a screenshot of the current browser page.",
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
          name: "browser_get_page_info",
          description: "Get the current page title, URL, and a list of interactive elements (links, buttons, inputs) with their CSS selectors.",
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
          name: "browser_scroll",
          description: "Scroll the browser page. Supports relative scrolling (up/down by pixel amount) and absolute scrolling (top/bottom to jump to page extremes).",
          parameters: {
            type: "object",
            properties: {
              direction: {
                type: "string",
                enum: ["up", "down", "top", "bottom"],
                description: "Scroll direction: 'up'/'down' for relative scrolling, 'top'/'bottom' to jump to page extremes (default: down)"
              },
              amount: {
                type: "integer",
                description: "Scroll amount in pixels for up/down directions (default: 500, ignored for top/bottom)"
              }
            },
            required: []
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_press_key",
          description: "Send a key press to the browser. Optionally focus an element first by CSS selector. Useful for submitting forms (Enter), closing dialogs (Escape), tab navigation (Tab), and menu navigation (Arrow keys).",
          parameters: {
            type: "object",
            properties: {
              key: {
                type: "string",
                enum: ["Enter", "Escape", "Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Backspace", "Space"],
                description: "The key to press"
              },
              selector: {
                type: "string",
                description: "Optional CSS selector of an element to focus before pressing the key"
              }
            },
            required: ["key"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_select",
          description: "Select an option from a <select> dropdown element. Match by value or visible text. If no match is found, returns the list of available options.",
          parameters: {
            type: "object",
            properties: {
              selector: {
                type: "string",
                description: "CSS selector of the <select> element"
              },
              value: {
                type: "string",
                description: "Option value to select (matches the 'value' attribute)"
              },
              text: {
                type: "string",
                description: "Option text to select (partial match on visible text)"
              }
            },
            required: ["selector"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "browser_back",
          description: "Navigate back in the browser history (like clicking the browser's Back button).",
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
          name: "browser_forward",
          description: "Navigate forward in the browser history (like clicking the browser's Forward button).",
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
          name: "stop_browser",
          description: "Stop the interactive browser session and close the browser.",
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        }
      }
    ].freeze

    def self.tools
      TOOLS + INTERACTIVE_TOOLS
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

        response = {
          success: true,
          message: "Successfully captured #{screenshots.length} screenshots.",
          screenshots: screenshots,
          filenames: screenshots.join("\n"),
          gallery_html: gallery_html,
          display_instruction: "Display the images using the gallery_html provided."
        }

        # Send the first screenshot as _image for LLM vision (Claude)
        response[:_image] = screenshots.first if screenshots.first

        response
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

    # Interactive browser methods

    MAX_BROWSER_ACTIONS = 20
    MAX_CONSECUTIVE_SAME_ACTION = 3

    def browser_action_guard!(action_name = nil)
      @browser_action_count ||= 0
      @browser_action_count += 1

      # Check total action limit
      if @browser_action_count > MAX_BROWSER_ACTIONS
        return {
          success: false,
          error: "Action limit reached (#{MAX_BROWSER_ACTIONS} actions). Call stop_browser to end the session, then start_browser to begin a new one.",
          action_count: @browser_action_count
        }
      end

      # Check consecutive same-action limit
      if action_name
        @browser_last_action ||= nil
        @browser_consecutive_count ||= 0

        if action_name == @browser_last_action
          @browser_consecutive_count += 1
        else
          @browser_last_action = action_name
          @browser_consecutive_count = 1
        end

        if @browser_consecutive_count > MAX_CONSECUTIVE_SAME_ACTION
          return {
            success: false,
            error: "Same action '#{action_name}' called #{@browser_consecutive_count} times consecutively. Try a different approach: use browser_screenshot to see the current page, or ask the user which element to interact with.",
            suggestion: "If you cannot find the right element, ask the user for guidance instead of retrying.",
            actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
          }
        end
      end

      nil
    end

    def start_browser(url:)
      if error = check_selenium_or_error
        return error
      end

      unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
        return { success: false, error: "Invalid URL format. Please provide a valid HTTP or HTTPS URL." }
      end

      # Reset all counters on new session
      @browser_action_count = 0
      @browser_last_action = nil
      @browser_consecutive_count = 0

      output = send_command(command: "web_navigator.py --action start --url #{Shellwords.escape(url)}", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      # Build response with noVNC link and screenshot
      response = {
        success: true,
        message: "Browser session started (max #{MAX_BROWSER_ACTIONS} actions). Users can watch at: http://localhost:7900",
        novnc_url: "http://localhost:7900",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_navigate(url:)
      if limit_error = browser_action_guard!("navigate")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
        return { success: false, error: "Invalid URL format. Please provide a valid HTTP or HTTPS URL." }
      end

      output = send_command(command: "web_navigator.py --action navigate --url #{Shellwords.escape(url)}", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Navigated to #{result.dig(:page_info, :url) || url}",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_click(selector:, description: nil)
      if limit_error = browser_action_guard!("click")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action click --selector #{Shellwords.escape(selector)}", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Clicked element: #{description || selector}",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_type(selector:, text:)
      if limit_error = browser_action_guard!("type")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action type --selector #{Shellwords.escape(selector)} --text #{Shellwords.escape(text)}", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Typed text into #{selector}",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_screenshot
      if limit_error = browser_action_guard!("screenshot")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action screenshot", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Screenshot captured.",
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_get_page_info
      if limit_error = browser_action_guard!("get_page_info")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action get_page_info", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      {
        success: true,
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }
    end

    def browser_scroll(direction: "down", amount: 500)
      if limit_error = browser_action_guard!("scroll")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action scroll --direction #{Shellwords.escape(direction)} --amount #{amount.to_i}", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      scroll_msg = %w[top bottom].include?(direction) ? "Scrolled to #{direction} of page" : "Scrolled #{direction} by #{amount}px"
      response = {
        success: true,
        message: scroll_msg,
        scroll: result[:scroll],
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_press_key(key:, selector: nil)
      if limit_error = browser_action_guard!("press_key")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      cmd = "web_navigator.py --action press_key --key #{Shellwords.escape(key)}"
      cmd += " --selector #{Shellwords.escape(selector)}" if selector

      output = send_command(command: cmd, container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Pressed key: #{key}#{selector ? " on #{selector}" : ""}",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_select(selector:, value: nil, text: nil)
      unless value || text
        return { success: false, error: "Either 'value' or 'text' parameter is required for browser_select." }
      end

      if limit_error = browser_action_guard!("select")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      cmd = "web_navigator.py --action select --selector #{Shellwords.escape(selector)}"
      cmd += " --value #{Shellwords.escape(value)}" if value
      cmd += " --text #{Shellwords.escape(text)}" if text

      output = send_command(command: cmd, container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Selected option in #{selector}",
        selected: result[:selected],
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_back
      if limit_error = browser_action_guard!("back")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action back", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Navigated back",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def browser_forward
      if limit_error = browser_action_guard!("forward")
        return limit_error
      end
      if error = check_selenium_or_error
        return error
      end

      output = send_command(command: "web_navigator.py --action forward", container: "python")
      result = parse_navigator_response(output)
      return result unless result[:success]

      response = {
        success: true,
        message: "Navigated forward",
        page_info: result[:page_info],
        actions_remaining: MAX_BROWSER_ACTIONS - @browser_action_count
      }

      if result[:screenshot]
        response[:screenshot] = result[:screenshot]
        response[:gallery_html] = create_screenshot_gallery([result[:screenshot]])
        response[:_image] = result[:screenshot]
      end

      response
    end

    def stop_browser
      output = send_command(command: "web_navigator.py --action stop", container: "python")
      result = parse_navigator_response(output)

      {
        success: true,
        message: result[:message] || "Browser session ended."
      }
    end

    private

    def parse_navigator_response(output)
      # The output from send_command includes prefix text; find the JSON portion
      json_match = output.match(/\{.+\}/m)
      unless json_match
        return { success: false, error: "No JSON response from web navigator. Output: #{output[0..200]}" }
      end

      begin
        parsed = JSON.parse(json_match[0], symbolize_names: true)
        parsed
      rescue JSON::ParserError => e
        { success: false, error: "Failed to parse navigator response: #{e.message}" }
      end
    end

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
