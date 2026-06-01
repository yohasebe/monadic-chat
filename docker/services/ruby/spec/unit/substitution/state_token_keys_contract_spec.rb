# frozen_string_literal: true

require_relative "../../spec_helper"

# Invariant contract for the session-state vocabulary tokens.
#
# The ${LAST_IMAGE}/${NOTEBOOK} resolvers in vocabulary.rb READ specific
# session keys that the image-generator and Jupyter tools WRITE. The two sides
# live in different files, and a rename on either side would make the resolver
# silently return nil (failure_mode :open) — the variable would quietly stop
# resolving with no error. These greps lock the key names on both sides so such
# a drift fails loudly here instead. See concerns review (#4), 2026-06-01.
RSpec.describe "session-state token key contract" do
  ruby_root = File.expand_path("../../..", __dir__) # docker/services/ruby
  vocab     = File.read(File.join(ruby_root, "lib/monadic/substitution/vocabulary.rb"))
  img_tools = File.read(File.join(ruby_root, "apps/image_generator/image_generator_tools.rb"))
  jup_tools = File.read(File.join(ruby_root, "apps/jupyter_notebook/jupyter_notebook_tools.rb"))

  it "keeps the unified monadic_state 'last_images' slot in sync (resolver reads / tools write)" do
    expect(vocab).to include("last_images"),
      "vocabulary.rb resolver should read the 'last_images' monadic_state slot"
    expect(img_tools).to include('key: "last_images"'),
      "image_generator_tools.rb should still save via monadic_save_state key: \"last_images\""
  end

  it "keeps the legacy *_last_image fallback keys in sync (resolver reads / tools write)" do
    %i[openai grok gemini3].each do |provider|
      key = ":#{provider}_last_image"
      expect(vocab).to include(key),
        "vocabulary.rb resolver should fall back to session[#{key}]"
      expect(img_tools).to include(key),
        "image_generator_tools.rb should still write session[#{key}]"
    end
  end

  it "keeps 'notebook_filename' in sync (resolver reads / Jupyter tools write)" do
    expect(vocab).to include("notebook_filename"),
      "vocabulary.rb resolver should read 'notebook_filename' from the context slot"
    expect(jup_tools).to include("notebook_filename"),
      "jupyter_notebook_tools.rb should still persist 'notebook_filename'"
  end
end
