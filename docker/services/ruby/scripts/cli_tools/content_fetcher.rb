#!/usr/bin/env ruby

# Get the filepath from command line arguments
filepath = ARGV[0]
# Get the sizecap from command line arguments, defaulting to 10MB
sizecap = (ARGV[1] || 10_000_000).to_i 

begin
  # Check if a filepath was provided
  if filepath.nil?
    puts "ERROR: No filepath provided."
    exit 1
  end

  # Check if the file exists and is readable
  unless File.readable?(filepath)
    puts "ERROR: File #{filepath} does not exist or is not readable."
    exit 1
  end

  # Get the file size
  file_size = File.size(filepath)
  # Check if the file size exceeds the sizecap
  if file_size > sizecap
    puts "WARNING: File size exceeds sizecap (#{file_size} bytes > #{sizecap} bytes). Only the first #{sizecap} bytes will be read."
  end

  # Open the file in read mode with UTF-8 encoding
  File.open(filepath, "r:UTF-8") do |f|
    begin
      # Read a sample of the file to check content
      sample = f.read(1024)
      
      # Define what we consider as binary content
      # This regex looks for common control characters that shouldn't appear in text files
      # excluding normal whitespace characters (space, tab, CR, LF)
      binary_regex = /[\x00-\x08\x0B\x0C\x0E-\x1A]/.freeze
      
      # Check if the sample contains binary content
      if sample.match?(binary_regex)
        puts "ERROR: The file appears to be binary."
        exit 1
      end
      
      # Rewind the file pointer to the beginning of the file
      f.rewind 

      # Read up to sizecap bytes from the file
      content = f.read(sizecap)
      
      # Verify the content is valid UTF-8
      if content.valid_encoding?
        puts content
      else
        # Try to handle content as UTF-8 with invalid character replacement
        cleaned_content = content.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '')
        puts cleaned_content
      end

    rescue ArgumentError => e 
      puts "ERROR: Invalid byte sequence in the file. It might be a binary file. (#{e.message})"
      exit 1
    end
  end

rescue StandardError => e
  puts "An error occurred: #{e.message}"
  exit 1
end
