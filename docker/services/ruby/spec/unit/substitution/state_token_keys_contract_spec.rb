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

  # The image tools place images in the chat's folder; what a reply made is
  # recorded on its message, which ${LAST_GENERATED_IMAGE} reads.
  it "keeps the made-image record in sync (resolver reads / the workbench records)" do
    record = File.read(File.join(ruby_root, "lib/monadic/workbench/record.rb"))
    expect(vocab).to include("Record.last_path"),
      "vocabulary.rb resolver should read the last made image from the messages' records"
    expect(record).to include("def last_path"),
      "record.rb should still define last_path"
  end

  # The notebook the Jupyter tools used last is what ${NOTEBOOK} reads:
  # asked of the resolver itself, after a tool made one.
  it "resolves ${NOTEBOOK} to the notebook a Jupyter tool made" do
    require_relative "../../../lib/monadic/shared_tools/jupyter_operations"
    require_relative "../../../lib/monadic/shared_tools/monadic_session_state"
    require_relative "../../../lib/monadic/substitution/vocabulary"
    app = Class.new do
      include MonadicSharedTools::JupyterOperations
      include Monadic::SharedTools::MonadicSessionState
    end.new
    chat = Monadic::Workspace::Ids.generate(:chat)
    session = { Monadic::Workspace::Chats::SESSION_KEY => chat, parameters: { "app_name" => "JupyterNotebookOpenAI" } }
    allow(Monadic::Workspace::Notebooks).to receive(:create).and_return("conversations/x_w/work/analysis.ipynb")

    app.create_jupyter_notebook(filename: "analysis", session: session)
    expect(Monadic::Substitution::Vocabulary.current_notebook(session)).to eq("conversations/x_w/work/analysis.ipynb")
  end
end
