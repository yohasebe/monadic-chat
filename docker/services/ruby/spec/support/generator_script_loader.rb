# frozen_string_literal: true

# Load a generator script into its OWN namespace.
#
# Generator scripts define their helpers at the top level, which in Ruby means
# on Object. Requiring two of them in one process therefore has the second
# silently overwrite the first's `get_api_key`, `generate_image` and friends —
# the Gemini spec worked only because it was the only script being loaded.
#
# instance_eval on a bare object reproduces top-level script semantics without
# that leak: `def` becomes a singleton method on the returned object, and code
# that calls its own helpers while loading (`X = resolve_something`) still
# resolves, because `self` is that same object. module_eval cannot do this —
# there the definitions are instance methods with no receiver to call them on.
#
# Constants are isolated as well: they land on the object's singleton class,
# so read them with `script.singleton_class.const_get(:NAME)`.
#
# The scripts' `__FILE__ == $PROGRAM_NAME` guards stay false here (the file is
# evaluated under its real path while $PROGRAM_NAME is rspec), so loading one
# never runs its CLI — and never reaches the paid API.
module GeneratorScriptLoader
  module_function

  def load(basename)
    path = File.expand_path("../../scripts/generators/#{basename}", __dir__)
    raise ArgumentError, "no such generator script: #{path}" unless File.exist?(path)

    script = Object.new
    script.instance_eval(File.read(path), path)
    script
  end
end
