# frozen_string_literal: true

module Monadic
  module Utils
    # Checks an app's reasoning setting against the model it names. Each
    # provider's request code reads `reasoning_effort` (and DeepSeek's
    # `reasoning_content`) and sends what the model takes: a listed value as
    # is, "none" as the model's way of reasoning least, anything else is left
    # out. So the one thing worth flagging is a value outside the model's own
    # list in model_spec.js (a typo or a level the model does not have): it is
    # silently not sent. Rules per provider are not repeated here; they drifted
    # from the request code once already.
    class MDSLValidator
      class << self
        def validate_reasoning_parameters(app_config, _provider, model)
          warnings = []
          model_spec = ModelSpec.get_model_spec(model)
          # An unknown model comes back as an empty entry, not nil.
          if model_spec.nil? || model_spec.empty?
            return { errors: ["Model '#{model}' not found in specifications"], warnings: [] }
          end

          %w[reasoning_effort reasoning_content].each do |key|
            value = app_config[key.to_sym] || app_config[key]
            next if value.nil? || value.to_s.empty? || value.to_s == "none"

            # Either [[levels], default] or a plain list of levels.
            listed = model_spec[key]
            levels = listed.is_a?(Array) && listed.first.is_a?(Array) ? listed.first : listed
            next unless levels.is_a?(Array) && levels.all? { |l| l.is_a?(String) } && !levels.empty?
            next if levels.include?(value.to_s)

            warnings << "#{key} '#{value}' is not a level #{model} takes (#{levels.join(', ')}); it is not sent"
          end
          { errors: [], warnings: warnings }
        end
      end
    end
  end
end