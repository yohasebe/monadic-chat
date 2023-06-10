# frozen_string_literal: true

def export_monadic
  # Execute the shell script to export the database
  success = system("./bin/export_db")

  # Check if the command was successful and return true or false
  if success
    puts "Database export successful."
    true
  else
    puts "Database export failed."
    false
  end
end

def import_monadic
  # Execute the shell script to import the database
  success = system("./bin/import_db")

  # Check if the command was successful and return true or false
  if success
    puts "Database import successful."
    true
  else
    puts "Database import failed."
    false
  end
end

# execute the following only if the file is directly run
# Main program
if $PROGRAM_NAME == __FILE__

  command = ARGV.shift

  case command
  when "export"
    export_monadic
  when "import"
    import_monadic
  end
end
