# frozen_string_literal: true

module Monadic
  module SharedTools
    module WebAutomation
      # Check if Selenium and Python containers are available
      def self.available?
        containers = `docker ps --format "{{.Names}}"`
        selenium_available = containers.include?("monadic-chat-selenium-container") || containers.include?("monadic_selenium")
        python_available = containers.include?("monadic-chat-python-container") || containers.include?("monadic_python")
        selenium_available && python_available
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
            description: "Extract text content from a web page in Markdown format",
            parameters: {
              type: "object",
              properties: {
                url: {
                  type: "string",
                  description: "The URL of the web page to extract text from"
                },
                use_image_recognition: {
                  type: "boolean",
                  description: "Use image recognition to extract text (useful when HTML parsing fails)"
                }
              },
              required: ["url"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "debug_application",
            description: "Debug a generated web application using Selenium",
            parameters: {
              type: "object",
              properties: {
                spec: {
                  type: "object",
                  description: "Specification with project name to debug"
                }
              },
              required: ["spec"]
            }
          }
        }
      ].freeze

      def self.tools
        TOOLS
      end
    end
  end
end
