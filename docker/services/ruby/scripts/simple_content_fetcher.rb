#!/usr/bin/env ruby

filepath = ARGV[0]
sizecap = ARGV[1] || 1_000_000

begin
  if filepath.nil?
    puts "ERROR: No filepath provided."
    exit 1
  end

  unless File.readable?(filepath)
    puts "ERROR: File #{filepath} does not exist or is not readable."
    exit 1
  end

  File.open(filepath, "r") do |f|
    res = f.read(sizecap)
    puts res
  end
rescue StandardError => e
  puts "An error occurred: #{e.message}"
end
