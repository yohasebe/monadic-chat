# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/library/manager'
require_relative '../../../lib/monadic/library/retriever'

# Signature-compatibility guard between the Knowledge Base app's tool calls
# and the Library API they invoke.
#
# Regression: the KB app passed a vestigial `scope: :kb` keyword that no
# Library method accepts, so list_conversations / search_library /
# get_conversation_details ALL raised "unknown keyword: :scope" (masked as a
# polite ❌ message by the tools' rescue, so nothing crashed and the breakage
# looked like a transient search error). Mocked specs never exercised the
# real signatures. This spec extracts the keywords the tools file actually
# passes and asserts — via reflection — that the real Library methods accept
# every one of them.
RSpec.describe 'KnowledgeBaseTools ↔ Library API signature compatibility' do
  TOOLS_SRC = File.read(
    File.expand_path('../../../apps/knowledge_base/knowledge_base_tools.rb', __dir__)
  )

  def accepted_keywords(method_obj)
    kinds = method_obj.parameters.map(&:first)
    return :any if kinds.include?(:keyrest) # **kwargs accepts everything

    method_obj.parameters
              .select { |kind, _| %i[key keyreq].include?(kind) }
              .map(&:last)
  end

  # Extract `keyword:` names passed inside the source call to `receiver.method(...)`.
  def passed_keywords(call_regex)
    m = TOOLS_SRC.match(call_regex)
    raise "call site not found: #{call_regex}" unless m

    m[1].scan(/(\w+):/).flatten.map(&:to_sym).uniq
  end

  {
    'Manager.list_conversations' => [
      Monadic::Library::Manager.method(:list_conversations),
      /Manager\.list_conversations\(\s*([\s\S]*?)\)/
    ],
    'Retriever.cascade_search' => [
      Monadic::Library::Retriever.method(:cascade_search),
      /Retriever\.cascade_search\(\s*query,\s*([\s\S]*?)\)/
    ],
    'Manager.get_conversation_details' => [
      Monadic::Library::Manager.method(:get_conversation_details),
      /Manager\.get_conversation_details\(\s*([\s\S]*?)\)/
    ]
  }.each do |label, (method_obj, call_regex)|
    it "#{label} accepts every keyword the KB tools pass" do
      accepted = accepted_keywords(method_obj)
      next if accepted == :any

      passed = passed_keywords(call_regex)
      unknown = passed - accepted
      expect(unknown).to be_empty,
        "#{label} does not accept #{unknown.inspect} (accepted: #{accepted.inspect})"
    end
  end

  it 'no vestigial scope: keyword remains in the KB tools' do
    expect(TOOLS_SRC).not_to match(/scope:\s*:kb/)
  end
end
