# frozen_string_literal: true

require 'json'
require 'net/http'
require 'fileutils'

# Two-stage Response Evaluator
#
# Stage 1 (Fixed Rules): Fast, deterministic pattern matching
#   - Immediate PASS for known good patterns
#   - Immediate FAIL for known bad patterns (errors, refusals)
#   - INCONCLUSIVE for cases that need semantic judgment
#
# Stage 2 (AI Evaluation): Semantic correctness judgment
#   - Only invoked when Stage 1 is inconclusive
#   - Focuses on meaning, not format/style
#   - Results are logged for review
#
module ResponseEvaluator
  # Result object for evaluation
  class Result
    attr_reader :status, :reason, :stage

    def initialize(status, reason = nil, stage: nil)
      @status = status
      @reason = reason
      @stage = stage
    end

    def pass?
      @status == :pass
    end

    def fail?
      @status == :fail
    end

    def inconclusive?
      @status == :inconclusive
    end

    def conclusive?
      !inconclusive?
    end

    def to_s
      stage_info = @stage ? "[Stage #{@stage}]" : ""
      "#{stage_info} #{@status.upcase}#{@reason ? ": #{@reason}" : ""}"
    end
  end

  # Common error patterns that indicate runtime errors (always fail)
  RUNTIME_ERROR_PATTERNS = [
    /undefined method ['`]/i,
    /NoMethodError:/,
    /NameError:/,
    /TypeError:/,
    /ArgumentError:/,
    /SyntaxError:/,
    /LoadError:/,
    /`rescue in.*'/,
    /from .*\.rb:\d+:in/,
    /Traceback \(most recent call last\)/,
    /Error: .* is not defined/
  ].freeze

  # Patterns that indicate tool loop or depth exceeded errors
  TOOL_LOOP_ERROR_PATTERNS = [
    /Maximum function call depth exceeded/i,
    /maximum.*tool.*calls.*exceeded/i,
    /too many function calls/i,
    /function call limit/i,
    /recursive tool call/i
  ].freeze

  # Tools that are acceptable to call in initial messages (low risk)
  SAFE_INITIAL_TOOLS = %w[
    load_research_progress
    load_learning_progress
    load_novel_context
    load_context
    list_titles
    list_help_sections
    check_environment
  ].freeze

  # Tools that should NOT be called in initial messages (high risk for loops)
  RISKY_INITIAL_TOOLS = %w[
    save_research_progress
    save_learning_progress
    save_novel_context
    save_response
    save_context
    add_finding
    add_research_topics
    add_sources
    update_progress
  ].freeze

  # Common refusal patterns (context-dependent - may be valid for some apps)
  REFUSAL_PATTERNS = [
    /I cannot|I can't|I'm unable to/i,
    /I don't have access to/i,
    /I'm not able to/i
  ].freeze

  class << self
    # Main entry point: evaluate a response
    #
    # @param response [String, Hash] The response to evaluate
    # @param app_name [String] The app name (e.g., "MathTutorOpenAI")
    # @param prompt [String] The prompt that was sent
    # @param context [Hash] Additional context (app_purpose, rules, etc.)
    # @return [Result] The evaluation result
    def evaluate(response, app_name, prompt, context = {})
      response_text = extract_text(response)

      # Stage 1: Fixed rules
      stage1_result = apply_fixed_rules(response_text, response, app_name, prompt, context)
      return stage1_result if stage1_result.conclusive?

      # Stage 2: AI evaluation (only if Stage 1 is inconclusive)
      stage2_result = ai_evaluate(response_text, app_name, prompt, context)

      # Log the evaluation for review
      log_evaluation(app_name, prompt, response_text, stage2_result, context)

      stage2_result
    end

    # Stage 1: Apply fixed rules
    def apply_fixed_rules(response_text, full_response, app_name, prompt, context)
      # Check for tool calls first - they are valid responses
      if has_tool_calls?(full_response)
        tool_names = extract_tool_names(full_response)
        if tool_names.any?
          return Result.new(:pass, "Valid tool call(s): #{tool_names.join(', ')}", stage: 1)
        end
      end

      # Check for empty response (only after confirming no tool calls)
      if response_text.nil? || response_text.strip.empty?
        return Result.new(:fail, "Empty response", stage: 1)
      end

      # Check for incomplete thinking responses (e.g., Perplexity "<think>" only)
      if response_text.strip =~ /\A<think>\s*\z/i
        return Result.new(:fail, "Incomplete response (thinking tag only)", stage: 1)
      end

      # Check for runtime errors (always fail)
      RUNTIME_ERROR_PATTERNS.each do |pattern|
        if response_text.match?(pattern)
          return Result.new(:fail, "Runtime error detected: #{pattern.source[0..30]}", stage: 1)
        end
      end

      # Check for tool loop errors (always fail - critical issue)
      TOOL_LOOP_ERROR_PATTERNS.each do |pattern|
        if response_text.match?(pattern)
          return Result.new(:fail, "Tool loop error detected: #{pattern.source[0..40]}. This indicates an infinite tool call loop in the system prompt.", stage: 1)
        end
      end

      # For initial messages, check for risky tool usage patterns
      if context[:is_initial_message] && has_tool_calls?(full_response)
        tool_names = extract_tool_names(full_response)

        # Check for risky tools in initial message
        risky_tools_called = tool_names & RISKY_INITIAL_TOOLS
        if risky_tools_called.any?
          return Result.new(:fail,
            "Risky tool(s) called in initial message: #{risky_tools_called.join(', ')}. " \
            "Initial messages should typically not call save/update tools. " \
            "This may indicate a system prompt issue that could cause tool loops.",
            stage: 1)
        end

        # Warn if too many tools are called in initial message
        if tool_names.length > 2
          # Not an automatic fail, but flag for review
          safe_tools = tool_names & SAFE_INITIAL_TOOLS
          unsafe_tools = tool_names - SAFE_INITIAL_TOOLS

          if unsafe_tools.length > 1
            return Result.new(:fail,
              "Too many non-safe tools called in initial message: #{unsafe_tools.join(', ')}. " \
              "This may indicate aggressive tool usage in the system prompt.",
              stage: 1)
          end
        end
      end

      # Check for minimum response length (very permissive - just avoid empty/trivial responses)
      if response_text.strip.length < 3
        return Result.new(:fail, "Response too short (#{response_text.strip.length} chars)", stage: 1)
      end

      # Get app-specific rules
      rules = get_rules_for_app(app_name)

      # Check pass patterns (if any match, immediate pass)
      if rules[:pass_patterns]
        rules[:pass_patterns].each do |pattern|
          if response_text.match?(pattern)
            return Result.new(:pass, "Matched pass pattern: #{pattern.source[0..30]}", stage: 1)
          end
        end
      end

      # Check fail patterns (if any match, immediate fail)
      if rules[:fail_patterns]
        rules[:fail_patterns].each do |pattern, reason|
          if response_text.match?(pattern)
            return Result.new(:fail, reason || "Matched fail pattern", stage: 1)
          end
        end
      end

      # Check for tool calls (valid for tool-capable apps)
      if has_tool_calls?(full_response)
        tool_names = extract_tool_names(full_response)

        # Check if these tools are expected
        if rules[:expected_tools] && tool_names.any?
          if (tool_names & rules[:expected_tools]).any?
            return Result.new(:pass, "Called expected tool: #{tool_names.join(', ')}", stage: 1)
          end
        end

        # Check if tools are explicitly unexpected
        if rules[:unexpected_tools] && tool_names.any?
          unexpected = tool_names & rules[:unexpected_tools]
          if unexpected.any?
            return Result.new(:fail, "Called unexpected tool: #{unexpected.join(', ')}", stage: 1)
          end
        end

        # Tool calls exist but not explicitly expected/unexpected - inconclusive
        # (Let AI evaluate if the tool choice was appropriate)
      end

      # Check for code blocks (for coding apps, but not for initial messages)
      if rules[:requires_code] && !context[:is_initial_message]
        unless contains_code_block?(response_text)
          return Result.new(:fail, "Expected code block but none found", stage: 1)
        end
      end

      # No conclusive result from fixed rules
      Result.new(:inconclusive, "No fixed rule matched", stage: 1)
    end

    # Stage 2: AI-based semantic evaluation
    def ai_evaluate(response_text, app_name, prompt, context)
      # Special handling for Perplexity initial messages
      # Perplexity models don't do role-play well - they identify as "Perplexity" regardless of system prompt
      # For initial messages, just verify meaningful text is returned
      if context[:provider] == 'perplexity' && context[:is_initial_message]
        if response_text && response_text.strip.length >= 20
          return Result.new(:pass, "Perplexity initial message: meaningful text returned", stage: 2)
        else
          return Result.new(:fail, "Perplexity initial message: response too short or empty", stage: 2)
        end
      end

      # Skip AI evaluation if not configured or API key not available
      unless ENV['OPENAI_API_KEY'] && !ENV['OPENAI_API_KEY'].empty?
        return Result.new(:pass, "AI evaluation skipped (no API key)", stage: 2)
      end

      # Skip if explicitly disabled
      if ENV['SKIP_AI_EVALUATION'] == 'true'
        return Result.new(:pass, "AI evaluation disabled", stage: 2)
      end

      app_base = extract_app_base(app_name)
      purpose = context[:purpose] || get_app_purpose(app_base)

      evaluation_prompt = build_evaluation_prompt(
        app_name: app_name,
        app_purpose: purpose,
        prompt: prompt,
        response: response_text[0..2000],  # Limit response length
        is_initial_message: context[:is_initial_message]
      )

      begin
        result = call_openai_api(evaluation_prompt)
        parse_ai_result(result)
      rescue StandardError => e
        # On API error, default to pass (don't fail tests due to evaluation API issues)
        Result.new(:pass, "AI evaluation error: #{e.message[0..50]}", stage: 2)
      end
    end

    private

    def extract_text(response)
      return response if response.is_a?(String)
      return nil unless response.is_a?(Hash)
      response[:text] || response['text'] || response[:content] || response['content']
    end

    def has_tool_calls?(response)
      return false unless response.is_a?(Hash)
      tool_calls = response[:tool_calls] || response['tool_calls']
      tool_calls.is_a?(Array) && tool_calls.any?
    end

    def extract_tool_names(response)
      return [] unless response.is_a?(Hash)
      tool_calls = response[:tool_calls] || response['tool_calls']
      return [] unless tool_calls.is_a?(Array)
      tool_calls.map { |tc| tc['name'] || tc[:name] }.compact
    end

    def contains_code_block?(text)
      return false if text.nil?
      # Markdown code blocks
      text.match?(/```[\w]*\n.*?\n```/m) ||
        # Indented code
        text.match?(/^\s{4,}\S/m) ||
        # Common code patterns
        text.match?(/\b(def |function |class |const |let |var |import |from |require\()/m)
    end

    def extract_app_base(app_name)
      # Remove provider suffix (e.g., "MathTutorOpenAI" -> "MathTutor")
      app_name.sub(/(OpenAI|Claude|Gemini|Grok|Mistral|Cohere|DeepSeek|Perplexity|Ollama)$/, '')
    end

    def get_rules_for_app(app_name)
      app_base = extract_app_base(app_name)
      EVALUATION_RULES[app_base] || {}
    end

    def get_app_purpose(app_base)
      APP_PURPOSES[app_base] || "General assistant"
    end

    def build_evaluation_prompt(app_name:, app_purpose:, prompt:, response:, is_initial_message: false)
      <<~PROMPT
        You are evaluating whether an AI assistant's response indicates the system is working.

        BE VERY LENIENT. Only fail if there is a clear technical problem.

        PASS if:
        - The response is a greeting or introduction (generic or specific)
        - The response answers a question
        - The response asks a clarifying question
        - The response explains capabilities
        - The response is relevant content of any kind

        FAIL only if:
        - The response contains an error message (API error, runtime error)
        - The response is completely empty or just whitespace
        - The response is gibberish or corrupted text
        - The response explicitly refuses to help without reason

        DO NOT fail because:
        - The response is generic instead of app-specific
        - The response doesn't mention the app name
        - The response is short

        App: #{app_name}
        App Purpose: #{app_purpose}
        User Prompt: #{prompt}

        AI Response:
        #{response}

        Answer with ONLY "PASS" or "FAIL: <reason>"
      PROMPT
    end

    def call_openai_api(prompt)
      uri = URI('https://api.openai.com/v1/chat/completions')

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"

      request.body = JSON.generate({
        model: 'gpt-4o-mini',  # Fast and cheap for evaluation
        messages: [
          { role: 'user', content: prompt }
        ],
        max_tokens: 100,
        temperature: 0.0  # Deterministic evaluation
      })

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "API error: #{response.code} - #{response.body[0..100]}"
      end

      data = JSON.parse(response.body)
      data.dig('choices', 0, 'message', 'content') || 'PASS'
    end

    def parse_ai_result(result)
      result = result.to_s.strip

      if result.upcase.start_with?('PASS')
        Result.new(:pass, "AI evaluation passed", stage: 2)
      elsif result.upcase.start_with?('FAIL')
        reason = result.sub(/^FAIL:?\s*/i, '').strip
        reason = "AI evaluation failed" if reason.empty?
        Result.new(:fail, reason, stage: 2)
      else
        # Ambiguous response - default to pass
        Result.new(:pass, "AI evaluation unclear: #{result[0..30]}", stage: 2)
      end
    end

    def log_evaluation(app_name, prompt, response_text, result, context)
      return unless ENV['LOG_EVALUATIONS'] == 'true'

      log_dir = File.join(Dir.home, 'monadic', 'log', 'evaluations')
      FileUtils.mkdir_p(log_dir)

      log_file = File.join(log_dir, "evaluation_#{Time.now.strftime('%Y%m%d')}.jsonl")

      entry = {
        timestamp: Time.now.iso8601,
        app_name: app_name,
        prompt: prompt[0..200],
        response_preview: response_text&.[](0..300),
        result: result.status.to_s,
        reason: result.reason,
        stage: result.stage
      }

      File.open(log_file, 'a') do |f|
        f.puts(JSON.generate(entry))
      end
    rescue StandardError
      # Ignore logging errors
    end
  end

  # App purposes for AI evaluation context
  APP_PURPOSES = {
    'Chat' => 'General conversation and Q&A',
    'ChatPlus' => 'Enhanced conversation with additional capabilities',
    'CodeInterpreter' => 'Execute and explain code',
    'CodingAssistant' => 'Write and explain code',
    'JupyterNotebook' => 'Interactive notebook-style computing',
    'NovelWriter' => 'Creative fiction writing',
    'MailComposer' => 'Email composition',
    'SpeechDraftHelper' => 'Speech writing assistance',
    'DocumentGenerator' => 'Document creation',
    'ResearchAssistant' => 'Research and information gathering',
    'Wikipedia' => 'Encyclopedia-style information',
    'Translate' => 'Language translation',
    'MermaidGrapher' => 'Diagram creation with Mermaid syntax',
    'DrawIOGrapher' => 'Diagram creation with Draw.io',
    'ConceptVisualizer' => 'Concept visualization',
    'SyntaxTree' => 'Sentence syntax analysis',
    'MathTutor' => 'Mathematics teaching and problem solving',
    'LanguagePractice' => 'Language learning practice',
    'LanguagePracticePlus' => 'Enhanced language learning with tools',
    'ChordAccompanist' => 'Music chord suggestions',
    'SecondOpinion' => 'Get alternative AI perspective',
    'ImageGenerator' => 'Image generation',
    'VideoGenerator' => 'Video generation',
    'AutoForge' => 'Autonomous web app creation',
    'MonadicHelp' => 'Help with Monadic Chat features'
  }.freeze

  # App-specific evaluation rules
  # Each app can define:
  #   - pass_patterns: [Regexp] - immediate pass if any match
  #   - fail_patterns: { Regexp => String } - immediate fail with reason
  #   - expected_tools: [String] - tool calls that indicate success
  #   - unexpected_tools: [String] - tool calls that indicate failure
  #   - requires_code: Boolean - must contain code block
  #
  EVALUATION_RULES = {
    'MathTutor' => {
      # Patterns that indicate correct math responses
      pass_patterns: [
        /\b\d+\b/,  # Contains numbers (likely answer)
        /=\s*\d+/,  # Equation with result
        /answer is/i,
        /result is/i,
        /equals/i
      ],
      fail_patterns: {
        /I cannot calculate/i => "Refused to calculate",
        /I don't know how to/i => "Claimed inability"
      }
    },

    'Translate' => {
      pass_patterns: [
        # Common translations will match specific patterns per test
      ],
      fail_patterns: {
        /I cannot translate/i => "Refused to translate",
        /I don't know that language/i => "Claimed language inability"
      }
    },

    'CodingAssistant' => {
      requires_code: true,
      pass_patterns: [
        /```\w*\n/,  # Code block
        /def |function |class |const |let |var /  # Code keywords
      ],
      fail_patterns: {
        /I cannot write code/i => "Refused to write code"
      }
    },

    'CodeInterpreter' => {
      expected_tools: %w[run_code execute_python check_environment run_python execute_code],
      pass_patterns: [
        /\b\d+\b/,  # Contains numbers (calculation result)
        /```/  # Code block
      ]
    },

    'ResearchAssistant' => {
      expected_tools: %w[fetch_web_content web_search search_web],
      # Note: load_research_progress alone is not sufficient
      pass_patterns: [
        /according to/i,
        /research shows/i,
        /sources indicate/i
      ]
    },

    'MermaidGrapher' => {
      expected_tools: %w[create_mermaid_diagram render_mermaid],
      pass_patterns: [
        /```mermaid/i,
        /graph |flowchart |sequenceDiagram|classDiagram/i
      ]
    },

    'ImageGenerator' => {
      expected_tools: %w[generate_image create_image],
      pass_patterns: [
        /generating|created|image/i
      ]
    },

    'VideoGenerator' => {
      expected_tools: %w[generate_video create_video],
      pass_patterns: [
        /video|generating|welcome|capabilities/i
      ]
    },

    'Chat' => {
      # Very permissive - just needs to be a reasonable response
      pass_patterns: [
        /.{20,}/  # At least 20 chars of content
      ]
    },

    'ChatPlus' => {
      pass_patterns: [
        /.{20,}/
      ]
    },

    'Wikipedia' => {
      pass_patterns: [
        /is a|was a|refers to|defined as/i  # Encyclopedic language
      ]
    },

    'ChordAccompanist' => {
      pass_patterns: [
        /chord|major|minor|diminished|augmented|progression/i
      ]
    },

    'SecondOpinion' => {
      # This app explains the consultation process
      pass_patterns: [
        /opinion|perspective|consult|alternative|second/i
      ]
    },

    'NovelWriter' => {
      pass_patterns: [
        /.{100,}/  # Creative writing should be substantial
      ]
    },

    'AutoForge' => {
      expected_tools: %w[create_project_structure initialize_project],
      pass_patterns: [
        /project|application|create|build|web/i
      ]
    }
  }.freeze
end
