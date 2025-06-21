# frozen_string_literal: true

# Lazy loading mechanism for heavy dependencies
module LazyLoader
  class << self
    def define_lazy_loader(constant_name, require_path, class_name = nil)
      # Remove the constant if it already exists
      if Object.const_defined?(constant_name)
        Object.send(:remove_const, constant_name)
      end

      # Define a new constant that loads on first access
      Object.const_set(constant_name, Module.new do
        @loaded = false
        @require_path = require_path
        @class_name = class_name || constant_name

        def self.const_missing(name)
          unless @loaded
            require @require_path
            @loaded = true
          end
          
          # Get the actual constant
          actual_const = @class_name.split('::').inject(Object) do |mod, const|
            mod.const_get(const)
          end
          
          # Replace the lazy module with the actual constant
          Object.send(:remove_const, constant_name)
          Object.const_set(constant_name, actual_const)
          
          # Return the requested constant
          actual_const.const_get(name)
        end

        def self.method_missing(method, *args, &block)
          unless @loaded
            require @require_path
            @loaded = true
          end
          
          # Get the actual constant
          actual_const = @class_name.split('::').inject(Object) do |mod, const|
            mod.const_get(const)
          end
          
          # Replace the lazy module with the actual constant
          Object.send(:remove_const, constant_name)
          Object.const_set(constant_name, actual_const)
          
          # Call the method on the actual constant
          actual_const.send(method, *args, &block)
        end
      end)
    end

    # Define lazy loaders for heavy dependencies
    def setup_lazy_loaders
      # Heavy gems that aren't needed immediately
      lazy_gems = {
        'Nokogiri' => 'nokogiri',
        'PragmaticSegmenter' => 'pragmatic_segmenter',
        'Rouge' => 'rouge',
        'Commonmarker' => 'commonmarker'
      }

      lazy_gems.each do |const_name, require_path|
        define_lazy_loader(const_name, require_path)
      end
    end
  end
end