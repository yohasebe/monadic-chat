# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenAIHelper DOCUMENT_MIME_TYPES" do
  it "includes standard document types" do
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/pdf")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/vnd.openxmlformats-officedocument.presentationml.presentation")
  end

  it "includes standard text types" do
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/csv")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/plain")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/markdown")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/html")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/xml")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/json")
  end

  it "includes code file MIME types" do
    # Python
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-python")
    # JavaScript
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/javascript")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/javascript")
    # TypeScript
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("application/typescript")
    # Ruby
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-ruby")
    # Java
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-java-source")
    # C/C++
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-c")
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-c++src")
    # Go
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-go")
    # Rust
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-rustsrc")
    # YAML
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/yaml")
    # Shell
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to include("text/x-shellscript")
  end

  it "is frozen" do
    expect(OpenAIHelper::DOCUMENT_MIME_TYPES).to be_frozen
  end
end
