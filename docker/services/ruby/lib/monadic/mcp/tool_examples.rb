# frozen_string_literal: true

module Monadic
  module MCP
    # Tool usage examples for better client understanding
    TOOL_EXAMPLES = {
      'find_help_topics' => {
        description: 'Search help with "text" parameter (not "query")',
        example: {
          text: 'syntax tree',
          top_n: 3
        }
      },
      'search_pdf' => {
        description: 'Search PDFs with "query" parameter',
        example: {
          query: 'machine learning',
          top_n: 5
        }
      },
      'run_code' => {
        description: 'Execute code with "language" and "code" parameters',
        example: {
          language: 'python',
          code: 'print("Hello, World!")'
        }
      },
      'dall_e_3' => {
        description: 'Generate images with DALL-E 3',
        example: {
          prompt: 'A serene Japanese garden in autumn',
          size: '1024x1024',
          quality: 'hd'
        }
      },
      'analyze_video' => {
        description: 'Analyze video content',
        example: {
          video_path: '/path/to/video.mp4',
          max_frames: 10
        }
      },
      'render_syntax_tree' => {
        description: 'Generate linguistic syntax trees',
        example: {
          sentence: 'The cat sat on the mat',
          language: 'english'
        }
      }
    }.freeze
  end
end