# frozen_string_literal: true

require "fileutils"
begin
  require "rspec/core/rake_task"
rescue LoadError
  # Allow listing/invoking non-RSpec tasks even if the gem isn't installed globally.
end
require "rubygems"
require_relative "./docker/services/ruby/lib/monadic/version"
version = Monadic::VERSION

# Unicode display width for proper terminal table alignment
begin
  require "unicode/display_width"
  UNICODE_DISPLAY_WIDTH_AVAILABLE = true
rescue LoadError
  UNICODE_DISPLAY_WIDTH_AVAILABLE = false
end

# Display-width-aware string padding helpers
# These methods pad strings based on terminal display width, not character count
module DisplayWidthHelpers
  def self.display_width(str)
    if UNICODE_DISPLAY_WIDTH_AVAILABLE
      Unicode::DisplayWidth.of(str)
    else
      str.length
    end
  end

  def self.ljust(str, width, padstr = ' ')
    current_width = display_width(str)
    padding_needed = [width - current_width, 0].max
    str + (padstr * padding_needed)
  end

  def self.rjust(str, width, padstr = ' ')
    current_width = display_width(str)
    padding_needed = [width - current_width, 0].max
    (padstr * padding_needed) + str
  end

  def self.center(str, width, padstr = ' ')
    current_width = display_width(str)
    padding_needed = [width - current_width, 0].max
    left_pad = padding_needed / 2
    right_pad = padding_needed - left_pad
    (padstr * left_pad) + str + (padstr * right_pad)
  end
end

# Set development environment variables if not in Docker container
unless File.file?("/.dockerenv")
  ENV['POSTGRES_HOST'] ||= 'localhost'
  ENV['POSTGRES_PORT'] ||= '5433'  # Use 5433 to avoid conflict with local PostgreSQL
  ENV['OPENAI_API_KEY'] ||= ENV['OPENAI_API_KEY']
  ENV['ANTHROPIC_API_KEY'] ||= ENV['ANTHROPIC_API_KEY']
  ENV['GEMINI_API_KEY'] ||= ENV['GEMINI_API_KEY']
  # Add other API keys as needed
end

# RSpec::Core::RakeTask.new(:spec) # Commented out as we define custom :spec task below

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new do |task|
    task.options = ["--config", "docker/services/ruby/.rubocop.yml"]
    task.patterns = ["docker/services/ruby/**/*.rb"]
  end
  task default: %i[spec rubocop]
rescue LoadError
  # RuboCop is not available, skip it
  task default: %i[spec]
end

# -----------------------------------------------------------------------------
# Task definitions live in rakelib/*.rake (loaded automatically by Rake):
#   build.rake       — packaging, vendor assets, platform builds
#   docs.rake        — docsify server, workflow SVG generation
#   help.rake        — help database build/export
#   lint.rake        — anti-pattern lint tasks
#   matrix.rake      — provider matrix tests
#   models.rake      — model spec synchronization
#   release.rake     — GitHub release management
#   server.rake      — server lifecycle, db tasks, aliases
#   test.rake        — rspec/jest/pytest suites and summaries
#   test_runner.rake — unified test runner (lib/test_runner.rb)
#   version.rake     — version consistency check/update
# -----------------------------------------------------------------------------
