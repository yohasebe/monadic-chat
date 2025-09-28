# frozen_string_literal: true

require 'erb'
require 'json'

module AutoForge
  module Utils
    module PromptBuilder
      extend self

      # Templates for single HTML file generation
      TEMPLATES = {
        single_html: <<~TEMPLATE
          Generate a complete, self-contained HTML application for: <%= app_name %>

          Description: <%= description %>

          Requirements:
          - Single HTML file with embedded CSS and JavaScript
          - No external dependencies (all code inline)
          - Modern, responsive design
          - Clean, well-structured code
          <% if features && features.any? %>

          Required Features:
          <% features.each do |feature| %>
          - <%= feature %>
          <% end %>
          <% end %>

          Technical Requirements:
          - Use semantic HTML5 elements
          - CSS should use CSS variables for theming
          - JavaScript should be vanilla JS (no frameworks)
          - Mobile-responsive design
          - Accessible (ARIA labels where appropriate)
        TEMPLATE
      }.freeze

      # Main entry point for prompt building
      def build_prompt_from_spec(spec, format: 'html', existing_content: nil)
        if format == 'cli'
          build_cli_prompt_from_spec(spec, existing_content)
        else
          # Default to HTML prompt building
          build_single_html_prompt(spec, existing_content: existing_content)
        end
      end

      # Build prompt for single HTML generation
      def build_single_html_prompt(spec, existing_content: nil, file_name: 'index.html')
        template = ERB.new(TEMPLATES[:single_html], trim_mode: '-')

        context = {
          app_name: spec[:name] || spec[:type] || "Web Application",
          description: spec[:description] || "A modern web application",
          features: spec[:features] || []
        }

        prompt = template.result_with_hash(context)

        if existing_content && !existing_content.strip.empty?
          prompt << <<~EXISTING

          Existing implementation (#{file_name}):
          ```html
          #{existing_content}
          ```

          Update the file above to satisfy every requirement. Respond with a unified diff patch targeting #{file_name}. Use standard `---` and `+++` headers and hunk markers. Do not wrap the patch in Markdown fences and do not include commentary.
          EXISTING
        else
          prompt << <<~NEW_FILE

          Output Instructions:
          - Provide only the complete HTML file content.
          - No explanations or Markdown fences.
          - Start with <!DOCTYPE html> and end with </html>.
          NEW_FILE
        end

        ensure_reasonable_length(prompt)
      end

      # Build prompt for CLI tool generation
      def build_cli_prompt_from_spec(spec, existing_content)
        name = spec[:name] || spec['name']
        description = spec[:description] || spec['description']
        features = spec[:features] || spec['features'] || []

        base_prompt = <<~PROMPT
          Project: #{name}
          Description: #{description}
          #{features.any? ? "Features:\n" + features.map { |f| "- #{f}" }.join("\n") : ""}
        PROMPT

        if existing_content
          <<~PROMPT
            Modify this existing CLI script:
            ```
            #{existing_content}
            ```

            Requirements:
            #{base_prompt}

            Generate the complete updated script. Output only code.
          PROMPT
        else
          base_prompt
        end
      end

      # Build prompt from template and context
      def build(template_key, context = {})
        template = TEMPLATES[template_key]
        raise ArgumentError, "Unknown template: #{template_key}" unless template

        erb = ERB.new(template, trim_mode: '-')
        prompt = erb.result_with_hash(context)
        ensure_reasonable_length(prompt)
      end

      # Add examples to prompt
      def add_examples(base_prompt, examples)
        return base_prompt if examples.nil? || examples.empty?

        examples_text = "\n\nExamples:\n"
        examples.each_with_index do |example, i|
          examples_text += "#{i + 1}. #{example}\n"
        end

        base_prompt + examples_text
      end

      # Add constraints to prompt
      def add_constraints(base_prompt, constraints)
        return base_prompt if constraints.nil? || constraints.empty?

        constraints_text = "\n\nConstraints:\n"
        constraints.each do |constraint|
          constraints_text += "- #{constraint}\n"
        end

        base_prompt + constraints_text
      end

      # Ensure prompt is not too long
      def ensure_reasonable_length(prompt, max_chars = 4000)
        return prompt if prompt.length <= max_chars

        # Truncate intelligently
        truncated = prompt[0...max_chars]
        last_sentence = truncated.rindex('.')

        if last_sentence && last_sentence > max_chars * 0.8
          truncated[0..last_sentence]
        else
          truncated + "..."
        end
      end

      # Create a simple instruction prompt
      def simple_prompt(instruction)
        ensure_reasonable_length(instruction)
      end

      # Format file list for context
      def format_file_context(files)
        return "" if files.nil? || files.empty?

        "\nExisting files in project:\n" +
        files.map { |f| "- #{f}" }.join("\n")
      end

      # Build error correction prompt
      def build_error_correction_prompt(original_prompt, error_message)
        <<~PROMPT
          The previous attempt resulted in an error:
          #{error_message}

          Please correct and retry.

          Original request:
          #{original_prompt}
        PROMPT
      end
    end
  end
end

# Inline tests
if __FILE__ == $0
  require 'minitest/autorun'

  class PromptBuilderTest < Minitest::Test
    include AutoForge::Utils::PromptBuilder

    def test_build_single_html_prompt
      spec = {
        name: "Calculator",
        description: "A simple calculator app",
        features: ["Basic arithmetic", "Clear button", "Keyboard support"]
      }

      prompt = build_single_html_prompt(spec)

      assert prompt.include?("Calculator")
      assert prompt.include?("simple calculator")
      assert prompt.include?("Basic arithmetic")
      assert prompt.include?("<!DOCTYPE html>")
      refute prompt.include?("```")
    end

    def test_add_examples
      base = "Create a function"
      examples = ["add(1, 2) => 3", "multiply(2, 3) => 6"]

      result = add_examples(base, examples)

      assert result.include?("Examples:")
      assert result.include?("add(1, 2)")
      assert result.include?("multiply(2, 3)")
    end

    def test_add_constraints
      base = "Build an app"
      constraints = ["No external dependencies", "Under 100 lines"]

      result = add_constraints(base, constraints)

      assert result.include?("Constraints:")
      assert result.include?("No external dependencies")
    end

    def test_ensure_reasonable_length
      long_text = "a" * 5000
      result = ensure_reasonable_length(long_text, 100)

      assert result.length <= 103
    end

    def test_format_file_context
      files = ["index.html", "styles.css", "app.js"]
      result = format_file_context(files)

      assert result.include?("Existing files")
      files.each { |f| assert result.include?(f) }
    end
  end

  puts "\n=== Running PromptBuilder Tests ==="
end
