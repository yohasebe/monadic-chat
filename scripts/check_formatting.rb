#!/usr/bin/env ruby
# Formatting checker for Monadic Chat codebase

require 'pathname'

class FormattingChecker
  PATTERNS = {
    string_with_space: /"\s{2,}[^"]*"/,
    space_before_paren: /\s+\)/,
    space_before_bracket: /\s+\]/,
    hash_space_issue: /\[\s*"[^"]+"\s*\]/,
    comma_space_issue: /,\s{2,}/
  }

  def initialize(directory = '.')
    @directory = Pathname.new(directory)
    @issues = []
  end

  def check_files
    ruby_files.each do |file|
      check_file(file)
    end
    report_issues
  end

  private

  def ruby_files
    Dir.glob(@directory.join('**', '*.rb')).reject do |f|
      f.include?('/tmp/') || f.include?('/vendor/') || f.include?('/.git/')
    end
  end

  def check_file(file)
    File.readlines(file).each_with_index do |line, index|
      PATTERNS.each do |name, pattern|
        if line.match?(pattern)
          @issues << {
            file: file,
            line: index + 1,
            issue: name,
            content: line.strip
          }
        end
      end
    end
  rescue => e
    puts "Error checking #{file}: #{e.message}"
  end

  def report_issues
    if @issues.empty?
      puts "✅ No formatting issues found!"
    else
      puts "Found #{@issues.length} formatting issues:\n\n"

      @issues.group_by { |i| i[:file] }.each do |file, file_issues|
        puts "📄 #{file}"
        file_issues.each do |issue|
          puts "  Line #{issue[:line]}: #{issue[:issue]}"
          puts "    #{issue[:content]}"
        end
        puts
      end
    end
  end
end

# Run the checker
if __FILE__ == $0
  checker = FormattingChecker.new(ARGV[0] || '.')
  checker.check_files
end