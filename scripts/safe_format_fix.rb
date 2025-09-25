#!/usr/bin/env ruby
# Safe formatting fixer - creates backup before making changes

require 'fileutils'
require 'pathname'

class SafeFormatFixer
  def initialize(file_or_dir, dry_run: true)
    @path = Pathname.new(file_or_dir)
    @dry_run = dry_run
    @changes = []
  end

  def fix
    if @path.directory?
      fix_directory(@path)
    else
      fix_file(@path)
    end

    report_changes
  end

  private

  def fix_directory(dir)
    Dir.glob(dir.join('**', '*.rb')).each do |file|
      next if file.include?('/tmp/') || file.include?('/vendor/')
      fix_file(Pathname.new(file))
    end
  end

  def fix_file(file)
    return unless file.exist?

    original_content = File.read(file)
    fixed_content = original_content.dup
    changes_made = []

    # Fix common issues
    # 1. Double spaces after commas in method calls (but not in strings)
    fixed_content.gsub!(/(\w+)\(\s*("[^"]*")\s*,\s{2,}/) do
      "#{$1}(#{$2}, "
    end

    # 2. Spaces before closing parentheses
    fixed_content.gsub!(/\s+\)/, ')')

    # 3. Hash access with extra spaces
    fixed_content.gsub!(/\["([^"]+)"\s+\]/, '["\\1"]')
    fixed_content.gsub!(/\[\s+"([^"]+)"\]/, '["\\1"]')

    # 4. Multiple spaces in concatenation
    fixed_content.gsub!(/" \s{2,}\+ "/, '" + "')

    if original_content != fixed_content
      if @dry_run
        @changes << {
          file: file.to_s,
          changes: count_changes(original_content, fixed_content)
        }
      else
        # Create backup
        backup_file = file.to_s + '.bak'
        FileUtils.cp(file, backup_file)

        # Write fixed content
        File.write(file, fixed_content)

        @changes << {
          file: file.to_s,
          backup: backup_file,
          changes: count_changes(original_content, fixed_content)
        }
      end
    end
  end

  def count_changes(original, fixed)
    original_lines = original.lines
    fixed_lines = fixed.lines

    changes = 0
    [original_lines.length, fixed_lines.length].max.times do |i|
      if original_lines[i] != fixed_lines[i]
        changes += 1
      end
    end

    changes
  end

  def report_changes
    if @changes.empty?
      puts "✅ No formatting issues found!"
    else
      if @dry_run
        puts "🔍 DRY RUN - Found issues in #{@changes.length} files:\n\n"
        @changes.each do |change|
          puts "  #{change[:file]} - #{change[:changes]} lines would be changed"
        end
        puts "\nRun with --fix to apply changes (backups will be created)"
      else
        puts "✅ Fixed #{@changes.length} files:\n\n"
        @changes.each do |change|
          puts "  #{change[:file]}"
          puts "    Backup: #{change[:backup]}"
          puts "    Changed: #{change[:changes]} lines"
        end
      end
    end
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.empty?
    puts "Usage: #{$0} <file_or_directory> [--fix]"
    puts "  Without --fix: dry run (shows what would be changed)"
    puts "  With --fix: applies changes and creates .bak files"
    exit 1
  end

  path = ARGV[0]
  dry_run = !ARGV.include?('--fix')

  fixer = SafeFormatFixer.new(path, dry_run: dry_run)
  fixer.fix
end