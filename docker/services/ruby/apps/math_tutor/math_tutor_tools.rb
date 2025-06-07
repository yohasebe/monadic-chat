class MathTutorOpenAI < MonadicApp
  include OpenAIHelper if defined?(OpenAIHelper)
  
  private
  
  def validate_math_input(expression)
    raise ArgumentError, "Expression cannot be empty" if expression.to_s.strip.empty?
    true
  end
end