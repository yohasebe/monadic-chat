# frozen_string_literal: true

# Scan floors shared by the lint scripts.
#
# A lint that reads nothing also finds nothing, so a renamed scan root, a
# misresolved ROOT or a broken glob would pass silently. Each lint counts
# what it read per scan root and hands the counts here with its floors; a
# count below its floor fails the lint before any --baseline is considered.
module ScanFloor
  module_function

  # Prints one summary line, plus one line per short root. Returns true when
  # every root meets its floor.
  def met?(tag, counts, floors)
    puts "[#{tag}] scanned #{floors.keys.map { |root| "#{root} #{counts.fetch(root, 0)}" }.join(', ')}"
    short = floors.select { |root, floor| counts.fetch(root, 0) < floor }
    short.each do |root, floor|
      puts "  #{root}: scanned #{counts.fetch(root, 0)} file(s), expected at least #{floor}"
    end
    short.empty?
  end
end
