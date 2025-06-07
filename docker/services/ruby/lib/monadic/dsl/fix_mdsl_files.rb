#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to fix MDSL files that have extra 'end' statements due to auto-completion bug

require 'fileutils'

class MDSLFixer
  def self.fix_file(mdsl_file)
    return unless File.exist?(mdsl_file)
    
    content = File.read(mdsl_file)
    
    # Check if file has the double-end pattern that indicates the bug
    # Look for patterns like:
    #   end
    #   end
    # end
    # Where the middle 'end' closes tools block and is duplicated
    
    if content.match(/^\s*end\s*\n\s*end\s*\n\s*end\s*$/m)
      puts "Found potential issue in: #{mdsl_file}"
      
      # Create backup
      backup_file = "#{mdsl_file}.fix_backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      FileUtils.cp(mdsl_file, backup_file)
      puts "  Created backup: #{backup_file}"
      
      # Fix the file by removing the duplicate 'end'
      # This regex finds the pattern where there's an extra 'end' after tools block
      fixed_content = content.gsub(/^(\s*end\s*\n)(\s*end\s*\n)(\s*end\s*$)/m, '\1\3')
      
      if fixed_content != content
        File.write(mdsl_file, fixed_content)
        puts "  Fixed: #{mdsl_file}"
        return true
      else
        puts "  No changes needed"
        return false
      end
    end
    
    false
  end
  
  def self.fix_all_mdsl_files(directory)
    fixed_count = 0
    
    Dir.glob(File.join(directory, "**/*.mdsl")).each do |mdsl_file|
      if fix_file(mdsl_file)
        fixed_count += 1
      end
    end
    
    puts "\nFixed #{fixed_count} files"
  end
end

# Run the fixer if called directly
if __FILE__ == $0
  if ARGV[0]
    if File.directory?(ARGV[0])
      MDSLFixer.fix_all_mdsl_files(ARGV[0])
    elsif File.file?(ARGV[0])
      MDSLFixer.fix_file(ARGV[0])
    else
      puts "Usage: #{$0} <directory_or_file>"
      exit 1
    end
  else
    # Default to apps directory
    apps_dir = File.expand_path("../../apps", __dir__)
    if File.directory?(apps_dir)
      MDSLFixer.fix_all_mdsl_files(apps_dir)
    else
      puts "Apps directory not found: #{apps_dir}"
      puts "Usage: #{$0} <directory_or_file>"
      exit 1
    end
  end
end