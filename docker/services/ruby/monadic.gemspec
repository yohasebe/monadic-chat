# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "monadic"
  spec.version = "1.0.0"
  spec.authors = ["yohasebe"]
  spec.email = ["yohasebe@gmail.com"]

  spec.summary = "Grounding AI Chatbots with Full Linux Environment on Docker"

  spec.description = <<~DESC
    Monadic Chat is a web client application program that uses OpenAI's Chat API to enable chat-style conversations with OpenAI's artificial intelligence system in a ChatGPT-like style.
  DESC
  spec.homepage = "https://github.com/yohasebe/monadic-chat"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.10"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/yohasebe/monadic-chat"
  spec.metadata["changelog_uri"] = "https://github.com/yohasebe/monadic-chat/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|circleci)|appveyor)})
    end
  end

  spec.bindir = "bin"
  spec.executables = ["monadic"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  # spec.add_development_dependency "rb_sys"
  # spec.add_development_dependency "rspec"
  # spec.add_development_dependency "solargraph"

  spec.add_dependency "activesupport"
  spec.add_dependency "cld"
  spec.add_dependency "dotenv"
  spec.add_dependency "faye-websocket"
  spec.add_dependency "http"
  spec.add_dependency "httparty"
  spec.add_dependency "http-form_data"
  spec.add_dependency "i18n_data"
  spec.add_dependency "kramdown"
  spec.add_dependency "kramdown-parser-gfm"
  spec.add_dependency "method_source"
  spec.add_dependency "nokogiri"
  spec.add_dependency "oj"
  spec.add_dependency "optimist"
  spec.add_dependency "pandoc-ruby"
  spec.add_dependency "parallel"
  spec.add_dependency "parslet"
  spec.add_dependency "pg"
  spec.add_dependency "pgvector"
  spec.add_dependency "pragmatic_segmenter"
  spec.add_dependency "rake"
  spec.add_dependency "redcarpet"
  spec.add_dependency 'rexml', '>= 3.3.9'
  spec.add_dependency "rouge"
  spec.add_dependency "sinatra"
  spec.add_dependency "thin"
end
