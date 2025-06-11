# frozen_string_literal: true

module MonadicChat
  # Core monadic operations following functional programming principles
  module Core
    # Basic monadic structure
    class MonadValue
      attr_reader :value, :context
      
      def initialize(value, context = {})
        @value = value
        @context = context || {}
      end
      
      # Convert to hash representation
      def to_h
        {
          "value" => @value,
          "context" => @context
        }
      end
      
      # Check if this is a valid monad
      def valid?
        !@value.nil?
      end
    end
    
    # == Core Operations ==
    
    # Wrap a value in monadic context (unit/return/pure)
    def wrap(value, context = {})
      MonadValue.new(value, context)
    end
    
    # Extract value from monadic context
    def unwrap(monad)
      case monad
      when MonadValue
        monad.value
      when Hash
        monad["value"] || monad["message"]
      else
        monad
      end
    end
    
    # Extract context from monadic structure
    def extract_context(monad)
      case monad
      when MonadValue
        monad.context
      when Hash
        monad["context"] || {}
      else
        {}
      end
    end
    
    # Transform the wrapped value (map/fmap)
    def transform(monad, &block)
      return monad unless block_given?
      
      value = unwrap(monad)
      context = extract_context(monad)
      
      new_value = yield(value)
      wrap(new_value, context)
    end
    
    # Transform the context
    def transform_context(monad, &block)
      return monad unless block_given?
      
      value = unwrap(monad)
      context = extract_context(monad)
      
      new_context = yield(context)
      wrap(value, new_context)
    end
    
    # Apply a function that returns a monad (bind/flatMap)
    def bind(monad, &block)
      return monad unless block_given?
      
      value = unwrap(monad)
      context = extract_context(monad)
      
      # The block should return a new monad
      result = yield(value, context)
      
      # Ensure result is monadic
      ensure_monadic(result)
    end
    
    # Combine two monadic values
    def combine(monad1, monad2, &block)
      value1 = unwrap(monad1)
      value2 = unwrap(monad2)
      context1 = extract_context(monad1)
      context2 = extract_context(monad2)
      
      # Merge contexts (later context takes precedence)
      merged_context = context1.merge(context2)
      
      # Combine values using provided block or default
      combined_value = if block_given?
                        yield(value1, value2)
                      else
                        [value1, value2]
                      end
      
      wrap(combined_value, merged_context)
    end
    
    # == Helper Methods ==
    
    private
    
    # Ensure a value is in monadic form
    def ensure_monadic(value)
      case value
      when MonadValue
        value
      when Hash
        if value.key?("value") || value.key?("message")
          wrap(value["value"] || value["message"], value["context"] || {})
        else
          wrap(value, {})
        end
      else
        wrap(value, {})
      end
    end
  end
end