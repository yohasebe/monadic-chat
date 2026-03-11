# frozen_string_literal: true

require_relative "../../spec_helper"
require 'shellwords'
require_relative "../../../lib/monadic/adapters/media_generation_helper"

RSpec.describe "MonadicHelper media generation shell escaping" do
  # Stub class that includes MonadicHelper and captures the command
  let(:helper_class) do
    Class.new do
      include MonadicHelper

      attr_reader :last_command

      def send_command(command:, container:)
        @last_command = command
        '{"success": true}'
      end
    end
  end
  let(:helper) { helper_class.new }

  describe "#generate_image_with_grok" do
    it "escapes prompt with special characters" do
      helper.generate_image_with_grok(prompt: 'a "blue" sky with $money', operation: "generate")
      expect(helper.last_command).to include("image_generator_grok.rb")
      expect(helper.last_command).not_to include('"blue"')
      # Shellwords.shellescape wraps or escapes special chars
      expect(helper.last_command).to include(Shellwords.shellescape('a "blue" sky with $money'))
    end

    it "escapes aspect_ratio parameter" do
      helper.generate_image_with_grok(prompt: "test", aspect_ratio: "16:9", operation: "generate")
      expect(helper.last_command).to include(Shellwords.shellescape("16:9"))
    end

    it "escapes image filenames with spaces" do
      helper.generate_image_with_grok(
        prompt: "edit",
        operation: "edit",
        images: ["/data/my image (1).png"]
      )
      expect(helper.last_command).to include(Shellwords.shellescape("/data/my image (1).png"))
    end

    it "prevents shell metacharacter injection in prompt" do
      dangerous_prompt = 'test; rm -rf / && echo "pwned"'
      helper.generate_image_with_grok(prompt: dangerous_prompt, operation: "generate")
      # The command should NOT contain unescaped semicolons or &&
      escaped = Shellwords.shellescape(dangerous_prompt)
      expect(helper.last_command).to include(escaped)
    end

    it "handles backtick injection attempts" do
      helper.generate_image_with_grok(prompt: 'test `whoami`', operation: "generate")
      expect(helper.last_command).to include(Shellwords.shellescape('test `whoami`'))
    end

    it "handles $() subshell injection attempts" do
      helper.generate_image_with_grok(prompt: 'test $(cat /etc/passwd)', operation: "generate")
      expect(helper.last_command).to include(Shellwords.shellescape('test $(cat /etc/passwd)'))
    end
  end

  describe "#generate_image_with_openai" do
    it "escapes prompt parameter" do
      helper.generate_image_with_openai(
        operation: "generate", model: "gpt-image-1", prompt: 'a "test" prompt'
      )
      expect(helper.last_command).to include(Shellwords.shellescape('a "test" prompt'))
    end

    it "escapes model parameter" do
      helper.generate_image_with_openai(
        operation: "generate", model: "gpt-image-1", prompt: "test"
      )
      expect(helper.last_command).to include(Shellwords.shellescape("gpt-image-1"))
    end

    it "formats numeric parameters safely" do
      helper.generate_image_with_openai(
        operation: "generate", model: "m", prompt: "test", n: 2
      )
      expect(helper.last_command).to include("-n 2")
    end

    it "escapes image paths" do
      helper.generate_image_with_openai(
        operation: "edit", model: "m", prompt: "edit",
        images: ["file with spaces.png"]
      )
      expect(helper.last_command).to include(Shellwords.shellescape("file with spaces.png"))
    end
  end

  describe "#generate_video_with_grok_imagine" do
    it "escapes prompt for video generation" do
      helper.generate_video_with_grok_imagine(prompt: 'a "cinematic" scene')
      expect(helper.last_command).to include(Shellwords.shellescape('a "cinematic" scene'))
    end

    it "formats numeric duration safely" do
      helper.generate_video_with_grok_imagine(prompt: "test", duration: 5)
      expect(helper.last_command).to include("5")
    end
  end

  describe "#generate_video_with_sora" do
    it "escapes prompt for sora video" do
      helper.generate_video_with_sora(prompt: 'test "scene"')
      expect(helper.last_command).to include(Shellwords.shellescape('test "scene"'))
    end

    it "escapes remix_video_id" do
      helper.generate_video_with_sora(prompt: "test", remix_video_id: "id-with spaces")
      expect(helper.last_command).to include(Shellwords.shellescape("id-with spaces"))
    end
  end
end
