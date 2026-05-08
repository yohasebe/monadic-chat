# frozen_string_literal: true

require 'spec_helper'

# Cross-cutting invariant: any capability flag that
# `MonadicDSL.finalize_capabilities!` resolves on the AppState
# (`state.settings[:library_save]`, `[:library_search]`,
# `[:privacy_enabled]`) must be carried into the generated runtime
# class definition. Otherwise the WebSocket app-data layer iterates
# the runtime instance's `@settings` and silently omits the key —
# the frontend body-class gate then defaults to "permissive" and
# renders UI surfaces (e.g. "Save to KB") that the app cannot
# legally use.
#
# Concrete failure mode this guards against (2026-05-08 Chat Plus):
# `privacy do; enabled true; end` triggered
# `state.settings[:library_save] = false` inside
# `finalize_capabilities!`, but the class-generation template only
# iterates `state.features.each` to populate `@settings`. The
# library_save=false directive lived in `state.settings` only,
# was missed by the iterator, and never reached the runtime
# instance. The frontend received no `library_save` key, defaulted
# to truthy, and showed the Save-to-KB button on a Privacy-only app.
#
# Detection strategy: load each MDSL into AppState, run
# `MonadicDSL.convert_to_class(state)`, and grep the resulting
# Ruby source for an explicit `@settings[:<flag>] = <value>` line
# whenever the AppState carries a non-nil value for that flag.

APPS_DIR_RT = File.expand_path('../../../apps', __dir__)

# Pre-require companion .rb files so MDSL eval has the symbols it
# needs (KnowledgeBaseConstants etc.). Mirrors the production load
# order in lib/monadic.rb#load_app_files.
Dir["#{APPS_DIR_RT}/**/*.rb"].sort.each do |f|
  begin
    require f
  rescue Exception # rubocop:disable Lint/RescueException
    # silently skip — capability_consistency_spec already surfaces
    # MDSL-level load failures
  end
end

RSpec.describe "Runtime capability propagation (class generation)" do
  # IMPORTANT — extend this list whenever a new finalize-style method is
  # added to MonadicDSL (i.e., something that writes to `state.settings[:foo]`
  # *after* the user's MDSL block has run, instead of through `state.features`).
  # The class-generation template's generic `state.features.each` loop will
  # silently skip such keys, so they need an explicit injection in
  # `convert_to_class` AND a corresponding entry here so this spec catches
  # any future regression of the same shape.
  CAPABILITY_KEYS = %i[library_save library_search privacy_enabled].freeze

  it "every state.settings capability flag is injected into the generated class definition" do
    discrepancies = []

    Dir["#{APPS_DIR_RT}/**/*.mdsl"].sort.each do |path|
      relative = path.sub("#{APPS_DIR_RT}/", '')
      state = MonadicDSL::Loader.load(path)
      # MonadicDSL.app(name) calls convert_to_class(state) inside, so by
      # this point the class is defined at TOPLEVEL_BINDING under
      # `state.name`. Look it up and inspect its class-level @settings.
      next unless state && state.name
      klass = begin
        Object.const_get(state.name)
      rescue NameError
        nil
      end
      next unless klass
      runtime_settings = klass.instance_variable_get(:@settings) || {}

      CAPABILITY_KEYS.each do |key|
        state_value = state.settings[key]
        next if state_value.nil?  # not declared / not derived → no contract

        runtime_value = runtime_settings[key]
        next if runtime_value == state_value

        discrepancies << "#{relative} key=#{key} state.settings=#{state_value.inspect} runtime @settings=#{runtime_value.inspect}"
      end
    end

    expect(discrepancies).to be_empty, <<~MSG
      The following MDSL files have capability flags resolved on
      AppState by finalize_capabilities! that are NOT carried into
      the generated class definition. The class-generation template
      in lib/monadic/dsl.rb (around `convert_to_class`) must inject
      every state.settings[:<flag>] explicitly when the generic
      `state.features.each` iterator does not already cover it.

      Discrepancies:
        #{discrepancies.join("\n  ")}
    MSG
  end
end
