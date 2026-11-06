# frozen_string_literal: true

require_relative "../../spec_helper"

# Invariant contract for the session-state vocabulary tokens.
#
# The ${LAST_GENERATED_IMAGE}/${NOTEBOOK} resolvers in vocabulary.rb READ specific
# session keys that the image-generator and Jupyter tools WRITE. The two sides
# live in different files, and a rename on either side would make the resolver
# silently return nil (failure_mode :open) — the variable would quietly stop
# resolving with no error. These greps lock the key names on both sides so such
# a drift fails loudly here instead. See concerns review (#4), 2026-06-01.
RSpec.describe "session-state token key contract" do
  ruby_root = File.expand_path("../../..", __dir__) # docker/services/ruby
  vocab     = File.read(File.join(ruby_root, "lib/monadic/substitution/vocabulary.rb"))
  jup_tools = File.read(File.join(ruby_root, "apps/jupyter_notebook/jupyter_notebook_tools.rb"))

  # The image tools place images in the chat's folder; what a reply made is
  # recorded on its message, which ${LAST_GENERATED_IMAGE} reads.
  it "keeps the made-image record in sync (resolver reads / the workbench records)" do
    record = File.read(File.join(ruby_root, "lib/monadic/workbench/record.rb"))
    expect(vocab).to include("Record.last_path"),
      "vocabulary.rb resolver should read the last made image from the messages' records"
    expect(record).to include("def last_path"),
      "record.rb should still define last_path"
  end

  it "keeps 'notebook_filename' in sync (resolver reads / Jupyter tools write)" do
    expect(vocab).to include("notebook_filename"),
      "vocabulary.rb resolver should read 'notebook_filename' from the context slot"
    expect(jup_tools).to include("notebook_filename"),
      "jupyter_notebook_tools.rb should still persist 'notebook_filename'"
  end
end
