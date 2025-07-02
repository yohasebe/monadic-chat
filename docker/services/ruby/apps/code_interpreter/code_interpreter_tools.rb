# This file is now empty - all Code Interpreter classes are defined via MDSL files
# The MDSL files handle class definitions, helper module inclusion, and settings

# Private helper methods shared by all Code Interpreter variants
module CodeInterpreterShared
  private
  
  def validate_code_input(code)
    raise ArgumentError, "Code cannot be empty" if code.to_s.strip.empty?
    true
  end
end