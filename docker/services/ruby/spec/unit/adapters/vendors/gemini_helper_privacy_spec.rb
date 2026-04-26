# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/monadic/adapters/vendors/gemini_helper'
require_relative '../../../../lib/monadic/utils/privacy/types'

RSpec.describe GeminiHelper, '#apply_privacy_to_gemini_contents' do
  subject(:helper) do
    Class.new { include GeminiHelper }.new
  end

  let(:fake_pipeline) do
    double('Pipeline').tap do |p|
      allow(p).to receive(:before_send_to_llm) do |raw|
        masked_text = raw.text.gsub(/Alice/, '<<PERSON_1>>')
        double('MaskedMessage', text: masked_text)
      end
    end
  end

  before do
    allow(helper).to receive(:privacy_pipeline_for).and_return(fake_pipeline)
  end

  it 'masks user-message text inside the parts array' do
    contents = [
      { "role" => "user", "parts" => [{ "text" => "Email Alice" }] }
    ]
    result = helper.send(:apply_privacy_to_gemini_contents, contents, {}, { privacy: { enabled: true } })
    expect(result[0]["parts"][0]["text"]).to eq("Email <<PERSON_1>>")
  end

  it 'leaves inline_data and file_data parts untouched' do
    contents = [{
      "role" => "user",
      "parts" => [
        { "text" => "Analyze Alice photo" },
        { "inline_data" => { "mime_type" => "image/png", "data" => "base64..." } },
        { "file_data" => { "mime_type" => "application/pdf", "file_uri" => "files/abc" } }
      ]
    }]
    result = helper.send(:apply_privacy_to_gemini_contents, contents, {}, { privacy: { enabled: true } })
    expect(result[0]["parts"][0]["text"]).to eq("Analyze <<PERSON_1>> photo")
    expect(result[0]["parts"][1]["inline_data"]["data"]).to eq("base64...")
    expect(result[0]["parts"][2]["file_data"]["file_uri"]).to eq("files/abc")
  end

  it 'does not mask model-role messages' do
    contents = [
      { "role" => "user", "parts" => [{ "text" => "Hi Alice" }] },
      { "role" => "model", "parts" => [{ "text" => "Hello Alice" }] }
    ]
    result = helper.send(:apply_privacy_to_gemini_contents, contents, {}, { privacy: { enabled: true } })
    expect(result[0]["parts"][0]["text"]).to eq("Hi <<PERSON_1>>")
    expect(result[1]["parts"][0]["text"]).to eq("Hello Alice")
  end

  it 'returns contents unchanged when pipeline is nil (privacy disabled)' do
    allow(helper).to receive(:privacy_pipeline_for).and_return(nil)
    contents = [{ "role" => "user", "parts" => [{ "text" => "Hi Alice" }] }]
    result = helper.send(:apply_privacy_to_gemini_contents, contents, {}, nil)
    expect(result).to eq(contents)
  end

  it 'handles symbol-key contents (parts: [{text: ...}])' do
    contents = [
      { role: "user", parts: [{ text: "Email Alice" }] }
    ]
    result = helper.send(:apply_privacy_to_gemini_contents, contents, {}, { privacy: { enabled: true } })
    expect(result[0][:parts][0][:text]).to eq("Email <<PERSON_1>>")
  end
end
