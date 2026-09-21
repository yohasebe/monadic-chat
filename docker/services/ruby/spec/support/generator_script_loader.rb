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
require "stringio"

module GeneratorScriptLoader
  module_function

  def load(basename)
    script = Object.new
    script.instance_eval(File.read(path_for(basename)), path_for(basename))
    script
  end

  # Same isolation, but with the script's `__FILE__ == $PROGRAM_NAME` guard
  # true, so the CLI block runs. The app reaches these scripts through their
  # command line, and a definition placed after the block that uses it is
  # invisible from there while every in-process example still passes — so the
  # CLI path needs exercising, not just the functions it calls.
  #
  # `load` would do this too, but it evaluates at the real top level and leaves
  # the script's methods on Object: one example's definitions would then be
  # available to the next, and a broken definition order would stop failing
  # after the first example had run.
  #
  # Returns [script, stdout]. ARGV, $PROGRAM_NAME and $stdout are restored.
  def run_cli(basename, argv)
    path = path_for(basename)
    previous = [$PROGRAM_NAME, ARGV.dup, $stdout]
    captured = StringIO.new
    script = Object.new
    begin
      $PROGRAM_NAME = path
      ARGV.replace(argv)
      $stdout = captured
      begin
        script.instance_eval(File.read(path), path)
      rescue SystemExit
        # `exit 1` on a rejected request is an outcome under test.
      end
    ensure
      $PROGRAM_NAME, restored_argv, $stdout = previous
      ARGV.replace(restored_argv)
    end
    [script, captured.string]
  end

  def path_for(basename)
    path = File.expand_path("../../scripts/generators/#{basename}", __dir__)
    raise ArgumentError, "no such generator script: #{path}" unless File.exist?(path)

    path
  end
end
