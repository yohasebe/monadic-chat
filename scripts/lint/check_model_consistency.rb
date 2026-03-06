#!/usr/bin/env ruby
# frozen_string_literal: true

# Model Lifecycle Consistency Checker
#
# Checks for model name inconsistencies across the codebase:
#   A. MDSL model references vs model_spec.js
#   B. providerDefaults consistency (all models exist in model_spec.js, none deprecated)
#   C. Sunset date alerts
#   D. Agent/helper hardcoded deprecated model references
#
# Usage:
#   ruby scripts/lint/check_model_consistency.rb
#   npm run lint:model-consistency

require "json"
require "date"
require "pathname"

module ModelConsistency
  ROOT = Pathname.new(__dir__).join("..", "..").realpath
  RUBY_SERVICE = ROOT.join("docker", "services", "ruby")
  APPS_DIR = RUBY_SERVICE.join("apps")
  SPEC_FILE = RUBY_SERVICE.join("public", "js", "monadic", "model_spec.js")

  # Directories to scan for hardcoded model references (Check D)
  AGENT_DIRS = [
    RUBY_SERVICE.join("lib", "monadic", "agents"),
    RUBY_SERVICE.join("lib", "monadic", "shared_tools")
  ].freeze

  AGENT_FILES = [
    RUBY_SERVICE.join("lib", "monadic", "app.rb")
  ].freeze

  # -------------------------------------------------------------------------
  # Issue
  # -------------------------------------------------------------------------
  Issue = Struct.new(:category, :file, :line, :model, :message, keyword_init: true)

  # -------------------------------------------------------------------------
  # SpecLoader — parse model_spec.js
  # -------------------------------------------------------------------------
  module SpecLoader
    module_function

    def load
      return {} unless SPEC_FILE.exist?

      js_content = SPEC_FILE.read

      if js_content =~ /const\s+modelSpec\s*=\s*\{/
        start_pos = js_content.index(/const\s+modelSpec\s*=\s*\{/)
        start_pos = js_content.index("{", start_pos)

        # Brace matching
        brace_count = 0
        end_pos = nil

        js_content[start_pos..-1].each_char.with_index do |char, i|
          if char == "{"
            brace_count += 1
          elsif char == "}"
            brace_count -= 1
            if brace_count == 0
              end_pos = start_pos + i
              break
            end
          end
        end

        return {} unless end_pos

        json_string = js_content[start_pos..end_pos]
        # Remove JS comments
        json_string = json_string.gsub(%r{//.*$}, "")
        json_string = json_string.gsub(%r{/\*.*?\*/}m, "")
        # Remove trailing commas
        json_string = json_string.gsub(/,(\s*[}\]])/, '\1')

        JSON.parse(json_string)
      else
        {}
      end
    rescue JSON::ParserError => e
      warn "Warning: Failed to parse model_spec.js: #{e.message}"
      {}
    end

    def deprecated_models(spec)
      spec.select { |_, props| props["deprecated"] == true }
    end

    def sunset_info(spec, model)
      props = spec[model] || {}
      {
        sunset_date: props["sunset_date"],
        successor: props["successor"]
      }
    end
  end

  # -------------------------------------------------------------------------
  # MdslChecker — Check A: MDSL ↔ model_spec.js
  # -------------------------------------------------------------------------
  module MdslChecker
    module_function

    # Extract model names from MDSL files
    # Handles: model "name" and model ["a", "b"]
    def extract_models_from_mdsl(file)
      results = []
      return results unless file.exist?

      file.each_line.with_index(1) do |line, lineno|
        # model "model-name"
        if line =~ /^\s*model\s+"([^"]+)"/
          results << { model: $1, line: lineno }
        # model ["model-a", "model-b", ...]
        elsif line =~ /^\s*model\s+\[(.+)\]/
          models_str = $1
          models_str.scan(/"([^"]+)"/).flatten.each do |m|
            results << { model: m, line: lineno }
          end
        end
      end
      results
    end

    def check(spec)
      issues = []
      deprecated = SpecLoader.deprecated_models(spec)

      mdsl_files = Dir.glob(APPS_DIR.join("**", "*.mdsl").to_s).map { |f| Pathname.new(f) }.sort

      mdsl_files.each do |file|
        rel = file.relative_path_from(ROOT)
        models = extract_models_from_mdsl(file)

        models.each do |entry|
          model = entry[:model]
          line = entry[:line]

          # Check: deprecated model referenced
          if deprecated.key?(model)
            info = SpecLoader.sunset_info(spec, model)
            msg = "references deprecated model"
            msg += " (sunset: #{info[:sunset_date]})" if info[:sunset_date]
            msg += " -> successor: #{info[:successor]}" if info[:successor]
            issues << Issue.new(category: :mdsl_deprecated, file: rel.to_s, line: line, model: model, message: msg)
          end

          # Check: model not in model_spec.js (not resolvable via normalization)
          unless model_exists_in_spec?(spec, model)
            issues << Issue.new(category: :mdsl_unknown, file: rel.to_s, line: line, model: model, message: "not found in model_spec.js")
          end
        end
      end

      issues
    end

    def model_exists_in_spec?(spec, model_name)
      return true if spec.key?(model_name)

      # Try normalized name (remove date suffixes)
      base = normalize_model_name(model_name)
      return true if base != model_name && spec.key?(base)

      false
    end

    # Simplified normalize — mirrors model_spec.rb logic
    def normalize_model_name(name)
      return name unless name.is_a?(String)

      # YYYY-MM-DD (OpenAI, xAI)
      return name.sub(/-\d{4}-\d{2}-\d{2}$/, "") if name =~ /-\d{4}-\d{2}-\d{2}$/

      # YYYYMMDD (Claude)
      if name =~ /-(\d{8})$/
        d = $1
        y, m, da = d[0..3].to_i, d[4..5].to_i, d[6..7].to_i
        return name.sub(/-\d{8}$/, "") if y >= 2020 && y <= 2030 && m >= 1 && m <= 12 && da >= 1 && da <= 31
      end

      # MM-YYYY (Cohere)
      if name =~ /-(\d{2})-(\d{4})$/
        m, y = $1.to_i, $2.to_i
        return name.sub(/-\d{2}-\d{4}$/, "") if y >= 2020 && y <= 2030 && m >= 1 && m <= 12
      end

      # -NNN (Gemini)
      return name.sub(/-\d{3}$/, "") if name =~ /-\d{3}$/

      name
    end
  end

  # -------------------------------------------------------------------------
  # DefaultsChecker — Check B: providerDefaults consistency
  # -------------------------------------------------------------------------
  module DefaultsChecker
    module_function

    def check(spec)
      issues = []
      provider_defaults = load_provider_defaults
      return issues if provider_defaults.empty?

      deprecated = SpecLoader.deprecated_models(spec)

      # Providers with dynamic/local models not tracked in model_spec.js
      skip_providers = %w[ollama].freeze

      provider_defaults.each do |provider, categories|
        next if skip_providers.include?(provider)
        next unless categories.is_a?(Hash)

        categories.each do |category, models|
          next unless models.is_a?(Array)

          models.each do |model|
            # Default model is deprecated
            if deprecated.key?(model)
              info = SpecLoader.sunset_info(spec, model)
              msg = "providerDefaults #{provider}/#{category} model is deprecated"
              msg += " (sunset: #{info[:sunset_date]})" if info[:sunset_date]
              msg += " -> successor: #{info[:successor]}" if info[:successor]
              issues << Issue.new(category: :defaults_deprecated, file: SPEC_FILE.relative_path_from(ROOT).to_s, line: nil, model: model, message: msg)
            end

            # Model not in spec (skip audio_transcription as those may not be in modelSpec)
            next if category == "audio_transcription"

            unless MdslChecker.model_exists_in_spec?(spec, model)
              issues << Issue.new(category: :defaults_unknown, file: SPEC_FILE.relative_path_from(ROOT).to_s, line: nil, model: model, message: "providerDefaults #{provider}/#{category} model not found in model_spec.js")
            end
          end
        end
      end

      issues
    end

    def load_provider_defaults
      return {} unless SPEC_FILE.exist?

      js_content = SPEC_FILE.read

      if js_content =~ /const\s+providerDefaults\s*=\s*\{/
        start_pos = js_content.index(/const\s+providerDefaults\s*=\s*\{/)
        start_pos = js_content.index("{", start_pos)

        brace_count = 0
        end_pos = nil

        js_content[start_pos..-1].each_char.with_index do |char, i|
          if char == "{"
            brace_count += 1
          elsif char == "}"
            brace_count -= 1
            if brace_count == 0
              end_pos = start_pos + i
              break
            end
          end
        end

        return {} unless end_pos

        json_string = js_content[start_pos..end_pos]
        json_string = json_string.gsub(%r{//.*$}, "")
        json_string = json_string.gsub(%r{/\*.*?\*/}m, "")
        json_string = json_string.gsub(/,(\s*[}\]])/, '\1')

        JSON.parse(json_string)
      else
        {}
      end
    rescue JSON::ParserError => e
      warn "Warning: Failed to parse providerDefaults from model_spec.js: #{e.message}"
      {}
    end
  end

  # -------------------------------------------------------------------------
  # SunsetChecker — Check C: sunset date alerts
  # -------------------------------------------------------------------------
  module SunsetChecker
    WARN_DAYS = 30

    module_function

    def check(spec)
      issues = []
      today = Date.today

      spec.each do |model, props|
        sunset_str = props["sunset_date"]
        next unless sunset_str

        begin
          sunset = Date.parse(sunset_str)
        rescue ArgumentError
          issues << Issue.new(category: :sunset_invalid, file: SPEC_FILE.relative_path_from(ROOT).to_s, line: nil, model: model, message: "invalid sunset_date format: #{sunset_str}")
          next
        end

        if sunset < today
          msg = "sunset date #{sunset_str} has already passed"
          msg += " (#{(today - sunset).to_i} days ago)"
          if props["deprecated"] == true
            # Already deprecated — informational only
            issues << Issue.new(category: :sunset_passed_deprecated, file: SPEC_FILE.relative_path_from(ROOT).to_s, line: nil, model: model, message: msg)
          else
            msg += " — WARNING: not marked as deprecated!"
            issues << Issue.new(category: :sunset_passed, file: SPEC_FILE.relative_path_from(ROOT).to_s, line: nil, model: model, message: msg)
          end
        elsif sunset <= today + WARN_DAYS
          msg = "sunset date #{sunset_str} is within #{WARN_DAYS} days"
          msg += " (#{(sunset - today).to_i} days remaining)"
          unless props["deprecated"] == true
            msg += " — WARNING: not yet marked as deprecated!"
          end
          issues << Issue.new(category: :sunset_approaching, file: SPEC_FILE.relative_path_from(ROOT).to_s, line: nil, model: model, message: msg)
        elsif !props["deprecated"]
          # Has sunset_date but not deprecated — informational
        end
      end

      issues
    end
  end

  # -------------------------------------------------------------------------
  # AgentChecker — Check D: hardcoded deprecated models in agents/helpers
  # -------------------------------------------------------------------------
  module AgentChecker
    # Pattern to match quoted model names in Ruby code
    MODEL_PATTERN = /["']([a-z][a-z0-9._:-]+)["']/

    module_function

    def check(spec)
      issues = []
      deprecated = SpecLoader.deprecated_models(spec)
      return issues if deprecated.empty?

      files = collect_files

      files.each do |file|
        rel = file.relative_path_from(ROOT)

        file.each_line.with_index(1) do |line, lineno|
          # Skip comment lines
          next if line =~ /^\s*#/

          line.scan(MODEL_PATTERN).flatten.each do |candidate|
            # Only flag if it exactly matches a deprecated model
            next unless deprecated.key?(candidate)

            info = SpecLoader.sunset_info(spec, candidate)
            msg = "references deprecated model"
            msg += " (sunset: #{info[:sunset_date]})" if info[:sunset_date]
            msg += " -> successor: #{info[:successor]}" if info[:successor]
            issues << Issue.new(category: :agent_deprecated, file: rel.to_s, line: lineno, model: candidate, message: msg)
          end
        end
      end

      issues.uniq { |i| [i.file, i.line, i.model] }
    end

    def collect_files
      files = []
      AGENT_DIRS.each do |dir|
        next unless dir.exist?

        files.concat(Dir.glob(dir.join("**", "*.rb").to_s).map { |f| Pathname.new(f) })
      end
      AGENT_FILES.each do |f|
        files << f if f.exist?
      end
      files.sort
    end
  end

  # -------------------------------------------------------------------------
  # Main
  # -------------------------------------------------------------------------
  def self.run
    spec = SpecLoader.load
    if spec.empty?
      warn "ERROR: Could not load model_spec.js"
      exit 1
    end

    all_issues = []
    all_issues.concat(MdslChecker.check(spec))
    all_issues.concat(DefaultsChecker.check(spec))
    all_issues.concat(SunsetChecker.check(spec))
    all_issues.concat(AgentChecker.check(spec))

    print_report(spec, all_issues)

    # Exit with 1 if any issues found (warnings are ok)
    exit 1 if all_issues.any? { |i| [:mdsl_deprecated, :mdsl_unknown, :defaults_deprecated, :defaults_unknown, :sunset_passed].include?(i.category) }
    exit 0
  end

  def self.print_report(spec, issues)
    deprecated_count = SpecLoader.deprecated_models(spec).size
    sunset_count = spec.count { |_, p| p["sunset_date"] }

    puts "Model Lifecycle Consistency Check"
    puts "=" * 60
    puts "Models in spec: #{spec.size}"
    puts "Deprecated models: #{deprecated_count}"
    puts "Models with sunset_date: #{sunset_count}"
    puts

    if issues.empty?
      puts "No issues found."
      return
    end

    # Group by category
    grouped = issues.group_by(&:category)

    category_labels = {
      mdsl_deprecated: "MDSL files referencing deprecated models",
      mdsl_unknown: "MDSL files referencing unknown models",
      defaults_deprecated: "Default models that are deprecated",
      defaults_unknown: "Default models not in model_spec.js",
      sunset_passed: "Models past sunset date (NOT marked deprecated!)",
      sunset_passed_deprecated: "Models past sunset date (already deprecated)",
      sunset_approaching: "Models approaching sunset date",
      sunset_invalid: "Models with invalid sunset_date",
      agent_deprecated: "Agent/helper files referencing deprecated models"
    }

    grouped.each do |category, cat_issues|
      label = category_labels[category] || category.to_s
      puts "#{label} (#{cat_issues.size}):"
      puts "-" * 56

      cat_issues.each do |issue|
        loc = issue.line ? "#{issue.file}:#{issue.line}" : issue.file
        puts "  #{loc}"
        puts "    #{issue.model} — #{issue.message}"
      end
      puts
    end

    error_count = issues.count { |i| [:mdsl_deprecated, :mdsl_unknown, :defaults_deprecated, :defaults_unknown, :sunset_passed].include?(i.category) }
    warn_count = issues.count { |i| [:sunset_approaching, :sunset_passed_deprecated, :agent_deprecated].include?(i.category) }

    puts "Summary: #{error_count} error(s), #{warn_count} warning(s)"
  end
end

ModelConsistency.run if $PROGRAM_NAME == __FILE__
