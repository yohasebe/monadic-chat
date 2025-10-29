# frozen_string_literal: true

require 'ostruct'

# Shared Tool Registry for Monadic Chat
# Centralizes tool group definitions with metadata for Progressive Tool Disclosure
#
# This registry provides:
# - Tool specifications (name, description, parameters)
# - Default unlock hints for PTD
# - Module references for implementation
#
# Usage:
#   MonadicSharedTools::Registry.tools_for(:file_operations)
#   # => [#<OpenStruct name="read_file_from_shared_folder", ...>, ...]

module MonadicSharedTools
  class Registry
    # Tool group definitions with complete metadata
    # Each group contains:
    # - module: The Ruby module containing the implementation
    # - tools: Array of tool specifications (name, description, parameters)
    # - default_hint: Default PTD unlock hint for this group
    TOOL_GROUPS = {
      file_operations: {
        module_name: 'MonadicSharedTools::FileOperations',
        tools: [
          {
            name: "read_file_from_shared_folder",
            description: "Read a file from the shared folder and return its content with metadata",
            parameters: [
              {
                name: :filepath,
                type: "string",
                description: "Relative or absolute path to the file (e.g., 'reports/summary.md')",
                required: true
              }
            ]
          },
          {
            name: "write_file_to_shared_folder",
            description: "Write or append content to a file in the shared folder with Unicode and subdirectory support",
            parameters: [
              {
                name: :filepath,
                type: "string",
                description: "Path to the file (relative to shared folder or absolute). Supports subdirectories and Unicode characters (e.g., 'プロジェクト/2025年/レポート.md')",
                required: true
              },
              {
                name: :content,
                type: "string",
                description: "Content to write to the file",
                required: true
              },
              {
                name: :mode,
                type: "string",
                description: "Write mode: 'write' to overwrite or 'append' to add to existing file (default: 'write')",
                required: false
              }
            ]
          },
          {
            name: "list_files_in_shared_folder",
            description: "List all files and directories in the shared folder or a subdirectory",
            parameters: [
              {
                name: :directory,
                type: "string",
                description: "Subdirectory to list (optional, defaults to root folder)",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"file_operations\") when you need to read, write, or list files in the shared folder."
      },

      python_execution: {
        module_name: 'MonadicSharedTools::PythonExecution',
        tools: [
          {
            name: "run_code",
            description: "Execute program code (Python, Ruby, Shell, etc.) and return the output",
            parameters: [
              {
                name: :code,
                type: "string",
                description: "Program code to execute",
                required: true
              },
              {
                name: :command,
                type: "string",
                description: "Execution command (e.g., 'python', 'ruby', 'bash')",
                required: true
              },
              {
                name: :extension,
                type: "string",
                description: "File extension (e.g., 'py', 'rb', 'sh')",
                required: true
              }
            ]
          },
          {
            name: "run_bash_command",
            description: "Execute a bash command in the Python container",
            parameters: [
              {
                name: :command,
                type: "string",
                description: "Bash command to execute",
                required: true
              }
            ]
          },
          {
            name: "check_environment",
            description: "Check the Python container environment (Dockerfile, packages)",
            parameters: []
          },
          {
            name: "lib_installer",
            description: "Install a library using package manager (pip, uv, or apt)",
            parameters: [
              {
                name: :command,
                type: "string",
                description: "Package name(s) to install",
                required: true
              },
              {
                name: :packager,
                type: "string",
                description: "Package manager to use: 'pip', 'uv', or 'apt' (default: 'pip')",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"python_execution\") when you need to run Python code, execute bash commands, or inspect the execution environment."
      },

      web_tools: {
        module_name: 'MonadicSharedTools::WebTools',
        tools: [
          {
            name: "search_web",
            description: "Search the web using provider-appropriate search method (native or Tavily)",
            parameters: [
              {
                name: :query,
                type: "string",
                description: "The search query",
                required: true
              },
              {
                name: :max_results,
                type: "integer",
                description: "Maximum number of results to return (default: 5)",
                required: false
              }
            ]
          },
          {
            name: "fetch_web_content",
            description: "Fetch content from a URL and save to shared folder",
            parameters: [
              {
                name: :url,
                type: "string",
                description: "The URL to fetch content from (HTTP/HTTPS)",
                required: true
              },
              {
                name: :timeout,
                type: "integer",
                description: "Request timeout in seconds (default: 10)",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"web_tools\") when you need to search the web or fetch content from URLs."
      },

      app_creation: {
        module_name: 'MonadicSharedTools::AppCreation',
        tools: [
          {
            name: "list_monadic_apps",
            description: "List all available Monadic Chat applications",
            parameters: []
          },
          {
            name: "get_app_info",
            description: "Get detailed information about a specific Monadic app",
            parameters: [
              {
                name: :app_name,
                type: "string",
                description: "Name of the app (e.g., 'chat_plus', 'code_interpreter')",
                required: true
              },
              {
                name: :variant,
                type: "string",
                description: "Provider variant (e.g., 'openai', 'claude'). Optional, defaults to first available.",
                required: false
              }
            ]
          },
          {
            name: "create_simple_app_template",
            description: "Create a basic Monadic app template file",
            parameters: [
              {
                name: :app_name,
                type: "string",
                description: "Name for the new app (snake_case, e.g., 'my_assistant')",
                required: true
              },
              {
                name: :display_name,
                type: "string",
                description: "Display name for the app (e.g., 'My Assistant')",
                required: true
              },
              {
                name: :provider,
                type: "string",
                description: "AI provider (e.g., 'openai', 'claude') (default: 'openai')",
                required: false
              },
              {
                name: :description,
                type: "string",
                description: "Brief description of the app",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"app_creation\") when you need to list, inspect, or create Monadic Chat applications."
      },

      file_reading: {
        module_name: 'MonadicSharedTools::FileReading',
        tools: [
          {
            name: "fetch_text_from_file",
            description: "Read text content from a file (txt, code, data files, etc.)",
            parameters: [
              {
                name: :file,
                type: "string",
                description: "Filename or path relative to shared folder (e.g., 'notes.txt', 'code/script.py')",
                required: true
              }
            ]
          },
          {
            name: "fetch_text_from_pdf",
            description: "Extract text content from a PDF file with full-page support",
            parameters: [
              {
                name: :file,
                type: "string",
                description: "Filename of the PDF to read (e.g., 'documents/report.pdf')",
                required: true
              }
            ]
          },
          {
            name: "fetch_text_from_office",
            description: "Extract text content from Office files (docx, xlsx, pptx)",
            parameters: [
              {
                name: :file,
                type: "string",
                description: "Filename of the Office file to read (e.g., 'reports/summary.docx')",
                required: true
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"file_reading\") when you need to read text from files, PDFs, or Office documents."
      },

      web_automation: {
        module_name: 'MonadicSharedTools::WebAutomation',
        tools: [
          {
            name: "capture_viewport_screenshots",
            description: "Capture a web page as multiple viewport-sized screenshots",
            parameters: [
              {
                name: :url,
                type: "string",
                description: "The URL of the web page to capture",
                required: true
              },
              {
                name: :viewport_width,
                type: "integer",
                description: "Width of the viewport in pixels (default: 1920)",
                required: false
              },
              {
                name: :viewport_height,
                type: "integer",
                description: "Height of the viewport in pixels (default: 1080)",
                required: false
              },
              {
                name: :overlap,
                type: "integer",
                description: "Number of pixels to overlap between screenshots (default: 100)",
                required: false
              },
              {
                name: :preset,
                type: "string",
                description: "Use preset viewport sizes: desktop, tablet, mobile, or print",
                required: false
              }
            ]
          },
          {
            name: "list_captured_screenshots",
            description: "List all screenshots captured in the current session",
            parameters: []
          },
          {
            name: "get_viewport_presets",
            description: "Get available viewport preset dimensions",
            parameters: []
          },
          {
            name: "capture_webpage_text",
            description: "Extract text content from a web page in Markdown format",
            parameters: [
              {
                name: :url,
                type: "string",
                description: "The URL of the web page to extract text from",
                required: true
              },
              {
                name: :use_image_recognition,
                type: "boolean",
                description: "Use image recognition to extract text (useful when HTML parsing fails)",
                required: false
              }
            ]
          },
          {
            name: "debug_application",
            description: "Debug a generated web application using Selenium",
            parameters: [
              {
                name: :spec,
                type: "object",
                description: "Specification with project name to debug",
                required: true
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"web_automation\") when you need to capture web pages as screenshots, extract webpage text, or debug web applications using Selenium."
      },

      video_analysis_openai: {
        module_name: 'MonadicSharedTools::VideoAnalysisOpenAI',
        tools: [
          {
            name: "analyze_video",
            description: "Analyze video content and generate description using OpenAI's multimodal capabilities (image recognition + audio transcription)",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The video file to analyze",
                required: true
              },
              {
                name: :fps,
                type: "integer",
                description: "Frames per second to extract (default: 1)",
                required: false
              },
              {
                name: :query,
                type: "string",
                description: "Query to guide the analysis",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"video_analysis\") when you need to analyze video content using image recognition and audio transcription."
      },

      jupyter_operations: {
        module_name: 'MonadicSharedTools::JupyterOperations',
        tools: [
          {
            name: "run_jupyter",
            description: "Start or stop JupyterLab server",
            parameters: [
              {
                name: :command,
                type: "string",
                description: "Command to run: 'start' or 'stop'",
                required: true
              }
            ]
          },
          {
            name: "create_jupyter_notebook",
            description: "Create a new Jupyter notebook with automatic timestamping",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "Base filename for the notebook (without .ipynb extension)",
                required: true
              }
            ]
          },
          {
            name: "add_jupyter_cells",
            description: "Add and optionally execute cells in a Jupyter notebook",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename (with or without .ipynb extension)",
                required: true
              },
              {
                name: :cells,
                type: "array",
                description: "Array of cell objects with 'cell_type' and 'source' fields",
                required: true
              },
              {
                name: :run,
                type: "boolean",
                description: "Whether to execute the cells after adding (default: true)",
                required: false
              },
              {
                name: :escaped,
                type: "boolean",
                description: "Whether content is escaped (default: false)",
                required: false
              }
            ]
          },
          {
            name: "delete_jupyter_cell",
            description: "Delete a cell from a Jupyter notebook by index",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              },
              {
                name: :index,
                type: "integer",
                description: "The zero-based index of the cell to delete",
                required: true
              }
            ]
          },
          {
            name: "update_jupyter_cell",
            description: "Update the content of an existing cell in a Jupyter notebook",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              },
              {
                name: :index,
                type: "integer",
                description: "The zero-based index of the cell to update",
                required: true
              },
              {
                name: :content,
                type: "string",
                description: "The new content for the cell",
                required: true
              },
              {
                name: :cell_type,
                type: "string",
                description: "The type of cell: 'code' or 'markdown' (default: 'code')",
                required: false
              }
            ]
          },
          {
            name: "get_jupyter_cells_with_results",
            description: "Get all cells with their execution results, including error information",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              }
            ]
          },
          {
            name: "execute_and_fix_jupyter_cells",
            description: "Execute cells with automatic error detection and optional retry",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              },
              {
                name: :max_retries,
                type: "integer",
                description: "Maximum number of retry attempts (default: 3)",
                required: false
              }
            ]
          },
          {
            name: "list_jupyter_notebooks",
            description: "List all Jupyter notebooks in the data directory",
            parameters: []
          },
          {
            name: "restart_jupyter_kernel",
            description: "Restart the kernel for a notebook and clear all outputs",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              }
            ]
          },
          {
            name: "interrupt_jupyter_execution",
            description: "Interrupt currently running cells in a notebook",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              }
            ]
          },
          {
            name: "move_jupyter_cell",
            description: "Move a cell to a new position in the notebook",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              },
              {
                name: :from_index,
                type: "integer",
                description: "The current zero-based index of the cell to move",
                required: true
              },
              {
                name: :to_index,
                type: "integer",
                description: "The target zero-based index position",
                required: true
              }
            ]
          },
          {
            name: "insert_jupyter_cells",
            description: "Insert cells at a specific position in the notebook",
            parameters: [
              {
                name: :filename,
                type: "string",
                description: "The notebook filename",
                required: true
              },
              {
                name: :index,
                type: "integer",
                description: "The zero-based position to insert cells at",
                required: true
              },
              {
                name: :cells,
                type: "array",
                description: "Array of cell objects to insert",
                required: true
              },
              {
                name: :run,
                type: "boolean",
                description: "Whether to execute the cells after inserting (default: false)",
                required: false
              }
            ]
          }
        ],
        default_hint: "Call request_tool(\"jupyter_operations\") when you need to create, manage, or execute Jupyter notebooks."
      }
    }

    # Get tool specifications for a given tool group
    #
    # @param group [Symbol] Tool group name (e.g., :file_operations)
    # @return [Array<OpenStruct>] Array of tool specification objects
    # @raise [ArgumentError] if group is unknown
    # @example
    #   tools = Registry.tools_for(:file_operations)
    #   tools.first.name # => "read_file_from_shared_folder"
    #   tools.first.description # => "Read a file from..."
    #   tools.first.parameters # => [{name: :filepath, type: "string", ...}]
    def self.tools_for(group)
      config = TOOL_GROUPS[group]
      raise ArgumentError, "Unknown tool group: #{group}. Available groups: #{TOOL_GROUPS.keys.join(', ')}" unless config

      # Convert tool specs to OpenStruct for easy access
      config[:tools].map do |spec|
        OpenStruct.new(spec)
      end
    end

    # Get the module name for a given tool group
    #
    # @param group [Symbol] Tool group name
    # @return [String] Module name
    # @raise [ArgumentError] if group is unknown
    # @example
    #   Registry.module_name_for(:file_operations)
    #   # => "MonadicSharedTools::FileOperations"
    def self.module_name_for(group)
      config = TOOL_GROUPS[group]
      raise ArgumentError, "Unknown tool group: #{group}" unless config

      config[:module_name]
    end

    # Get the default unlock hint for a given tool group
    #
    # @param group [Symbol] Tool group name
    # @return [String] Default unlock hint
    # @raise [ArgumentError] if group is unknown
    # @example
    #   Registry.default_hint_for(:file_operations)
    #   # => "Call request_tool(\"file_operations\") when you need to..."
    def self.default_hint_for(group)
      config = TOOL_GROUPS[group]
      return "" unless config

      config[:default_hint]
    end

    # Get all available tool group names
    #
    # @return [Array<Symbol>] List of tool group names
    # @example
    #   Registry.available_groups
    #   # => [:file_operations]
    def self.available_groups
      TOOL_GROUPS.keys
    end

    # Check if a tool group exists
    #
    # @param group [Symbol] Tool group name
    # @return [Boolean] true if group exists
    # @example
    #   Registry.group_exists?(:file_operations) # => true
    #   Registry.group_exists?(:unknown)          # => false
    def self.group_exists?(group)
      TOOL_GROUPS.key?(group)
    end
  end
end
