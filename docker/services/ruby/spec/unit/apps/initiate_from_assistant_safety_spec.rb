# frozen_string_literal: true

# Safety Validation for Apps with initiate_from_assistant: true
#
# This spec validates that apps which initiate conversations don't have
# system prompts that could cause infinite tool call loops.
#
# The problem pattern:
# 1. App has initiate_from_assistant: true (assistant sends first message)
# 2. System prompt has aggressive mandatory tool usage ("MUST", "MANDATORY", "CRITICAL ERROR")
# 3. Model follows instructions literally and calls tools repeatedly
# 4. Results in "Maximum function call depth exceeded" error
#
# The solution pattern:
# 1. Apps should have explicit initial greeting instructions
# 2. Tool usage should be "recommended" not "mandatory"
# 3. Clear stop conditions should be specified

require 'spec_helper'

RSpec.describe 'Initiate From Assistant Safety Validation' do
  let(:apps_dir) { File.expand_path('../../../apps', __dir__) }

  # Patterns that indicate aggressive/mandatory tool usage (high risk for loops)
  DANGEROUS_PATTERNS = [
    /MANDATORY.*TOOL/i,
    /YOU MUST USE THE PROVIDED TOOLS/i,
    /FAILURE TO CALL.*TOOLS.*IS.*CRITICAL/i,
    /FAILURE TO CALL.*TOOLS.*IS.*ERROR/i,
    /ABSOLUTE RULES.*\n.*ALWAYS call/i,
    /Before ANY response.*you MUST call/i,
    /NEVER skip tool calls/i,
    /tool calls.*are MANDATORY/i
  ].freeze

  # Patterns that indicate proper safeguards for initial messages
  SAFEGUARD_PATTERNS = [
    /initial greeting/i,
    /first.*message.*greet/i,
    /starting a.*session.*greet/i,
    /do NOT call.*tools.*initial/i,
    /do NOT call.*tools.*greeting/i,
    /without.*tools.*greeting/i,
    /respond.*directly.*greeting/i,
    /INITIAL GREETING/,
    /Welcome Message/i
  ].freeze

  # Patterns that indicate proper stop conditions after tool calls
  STOP_CONDITION_PATTERNS = [
    /after.*calling.*save.*your turn is COMPLETE/i,
    /after.*save.*do NOT call.*more tools/i,
    /your turn is COMPLETE.*do NOT call/i,
    /STOP.*do not call more tools/i
  ].freeze

  # Patterns for recommended (not mandatory) tool usage
  RECOMMENDED_PATTERNS = [
    /\(Recommended\)/i,
    /\(Optional.*recommended\)/i,
    /Use.*when appropriate/i,
    /you may.*call/i,
    /you can.*track/i
  ].freeze

  describe 'System prompt safety for initiate_from_assistant apps' do
    # Find all MDSL files with initiate_from_assistant true
    Dir.glob(File.join(File.expand_path('../../../apps', __dir__), '**/*.mdsl')).each do |mdsl_file|
      content = File.read(mdsl_file)
      next unless content.match?(/initiate_from_assistant\s+true/)

      relative_path = mdsl_file.sub(File.expand_path('../../../apps', __dir__) + '/', '')
      app_name = File.basename(mdsl_file, '.mdsl')

      context "#{relative_path}" do
        let(:file_content) { content }
        let(:system_prompt) do
          # Extract system_prompt content
          # Handle both inline and heredoc formats
          if content =~ /system_prompt\s+<<~TEXT\s*\n(.*?)\n\s*TEXT/m
            $1
          elsif content =~ /system_prompt\s+([A-Z][A-Za-z]+::[A-Z_]+)/
            # Reference to constant - need to check the constant file
            constant_ref = $1
            nil # Will be checked separately
          else
            nil
          end
        end

        it 'does not have dangerous mandatory tool patterns without safeguards' do
          skip "System prompt is a constant reference" if system_prompt.nil?

          dangerous_matches = DANGEROUS_PATTERNS.select { |pattern| system_prompt.match?(pattern) }

          if dangerous_matches.any?
            # Check if there are proper safeguards
            has_initial_greeting_safeguard = SAFEGUARD_PATTERNS.any? { |p| system_prompt.match?(p) }
            has_stop_condition = STOP_CONDITION_PATTERNS.any? { |p| system_prompt.match?(p) }
            has_recommended_language = RECOMMENDED_PATTERNS.any? { |p| system_prompt.match?(p) }

            if !has_initial_greeting_safeguard && !has_recommended_language
              fail <<~ERROR
                #{app_name} has dangerous mandatory tool patterns without proper safeguards!

                Dangerous patterns found:
                #{dangerous_matches.map { |p| "  - #{p.source}" }.join("\n")}

                Missing safeguards:
                #{!has_initial_greeting_safeguard ? "  - No initial greeting exception (e.g., 'Do NOT call tools for initial greeting')" : ""}
                #{!has_stop_condition ? "  - No stop condition after save (e.g., 'After calling save_*, your turn is COMPLETE')" : ""}
                #{!has_recommended_language ? "  - Tool usage is mandatory instead of recommended" : ""}

                This pattern can cause infinite tool call loops with 'Maximum function call depth exceeded' error.

                FIX: Either:
                1. Change "MANDATORY"/"MUST" language to "Recommended"/"when appropriate"
                2. Add explicit initial greeting exception
                3. Add clear stop condition after save operations
              ERROR
            end
          end
        end

        it 'has appropriate initial greeting handling' do
          skip "System prompt is a constant reference" if system_prompt.nil?

          # Apps with tools should have some guidance about initial messages
          has_tools = file_content.match?(/define_tool|import_shared_tools/)

          if has_tools
            has_any_safeguard = SAFEGUARD_PATTERNS.any? { |p| system_prompt.match?(p) } ||
                                STOP_CONDITION_PATTERNS.any? { |p| system_prompt.match?(p) } ||
                                system_prompt.match?(/for simple.*skip.*tools/i) ||
                                system_prompt.match?(/welcome.*message/i)

            # This is a warning, not a failure - some apps may legitimately need tools on first message
            if !has_any_safeguard && system_prompt.length > 500
              pending "Consider adding initial greeting guidance - app has tools but no explicit greeting instructions"
            end
          end
        end

        it 'does not have excessive CRITICAL/MANDATORY language' do
          skip "System prompt is a constant reference" if system_prompt.nil?

          # Count aggressive keywords
          critical_count = system_prompt.scan(/CRITICAL|MANDATORY|ABSOLUTE|MUST/i).length
          recommended_count = system_prompt.scan(/Recommended|Optional|when appropriate|you may|you can/i).length

          # If more than 5 aggressive keywords and ratio is poor, flag it
          if critical_count > 5 && recommended_count < 2
            pending <<~WARNING
              System prompt has high aggressive language ratio (#{critical_count} CRITICAL/MANDATORY vs #{recommended_count} recommended).
              Consider softening language to prevent potential tool loops.
            WARNING
          end
        end
      end
    end
  end

  describe 'Constant-based system prompts' do
    # Check apps that use constant references for system prompts
    constants_dir = File.expand_path('../../../apps', __dir__)

    Dir.glob(File.join(constants_dir, '**/*_constants.rb')).each do |constants_file|
      relative_path = constants_file.sub(constants_dir + '/', '')

      context "#{relative_path}" do
        let(:content) { File.read(constants_file) }

        it 'does not have dangerous mandatory patterns in SYSTEM_PROMPT constant' do
          # Extract SYSTEM_PROMPT if present
          if content =~ /SYSTEM_PROMPT\s*=\s*<<~TEXT\s*\n(.*?)\n\s*TEXT/m
            system_prompt = $1

            dangerous_matches = DANGEROUS_PATTERNS.select { |pattern| system_prompt.match?(pattern) }

            if dangerous_matches.any?
              has_safeguard = SAFEGUARD_PATTERNS.any? { |p| system_prompt.match?(p) } ||
                             STOP_CONDITION_PATTERNS.any? { |p| system_prompt.match?(p) }

              unless has_safeguard
                fail <<~ERROR
                  #{relative_path} SYSTEM_PROMPT has dangerous patterns without safeguards!
                  Patterns: #{dangerous_matches.map(&:source).join(', ')}
                ERROR
              end
            end
          end
        end
      end
    end
  end

  describe 'Tool usage patterns across all apps' do
    it 'reports summary of apps with initiate_from_assistant' do
      apps_with_initiate = []
      apps_with_tools_and_initiate = []
      apps_needing_review = []

      Dir.glob(File.join(apps_dir, '**/*.mdsl')).each do |mdsl_file|
        content = File.read(mdsl_file)
        next unless content.match?(/initiate_from_assistant\s+true/)

        relative_path = mdsl_file.sub(apps_dir + '/', '')
        has_tools = content.match?(/define_tool|import_shared_tools/)

        apps_with_initiate << relative_path

        if has_tools
          apps_with_tools_and_initiate << relative_path

          # Check for dangerous patterns
          if content =~ /system_prompt\s+<<~TEXT\s*\n(.*?)\n\s*TEXT/m
            system_prompt = $1
            has_dangerous = DANGEROUS_PATTERNS.any? { |p| system_prompt.match?(p) }
            has_safeguard = SAFEGUARD_PATTERNS.any? { |p| system_prompt.match?(p) } ||
                           STOP_CONDITION_PATTERNS.any? { |p| system_prompt.match?(p) }

            if has_dangerous && !has_safeguard
              apps_needing_review << relative_path
            end
          end
        end
      end

      # This test always passes but outputs useful info
      if ENV['DEBUG']
        puts "\n=== Initiate From Assistant Apps Summary ==="
        puts "Total apps with initiate_from_assistant: true: #{apps_with_initiate.length}"
        puts "Apps with tools AND initiate_from_assistant: #{apps_with_tools_and_initiate.length}"
        puts "Apps needing review (dangerous patterns without safeguards): #{apps_needing_review.length}"

        if apps_needing_review.any?
          puts "\nApps needing review:"
          apps_needing_review.each { |app| puts "  - #{app}" }
        end
      end

      expect(apps_needing_review).to be_empty,
        "Found #{apps_needing_review.length} apps with dangerous patterns: #{apps_needing_review.join(', ')}"
    end
  end
end
