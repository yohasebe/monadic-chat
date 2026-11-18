# frozen_string_literal: true

require_relative "../../spec_helper"
require 'shellwords'
require 'json'
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
      helper.generate_image_with_grok(prompt: 'a "blue" sky with $money', operation: "generate", out_dir: "/job")
      expect(helper.last_command).to include("image_generator_grok.rb")
      expect(helper.last_command).not_to include('"blue"')
      # Shellwords.shellescape wraps or escapes special chars
      expect(helper.last_command).to include(Shellwords.shellescape('a "blue" sky with $money'))
    end

    it "escapes aspect_ratio parameter" do
      helper.generate_image_with_grok(prompt: "test", aspect_ratio: "16:9", operation: "generate", out_dir: "/job")
      expect(helper.last_command).to include(Shellwords.shellescape("16:9"))
    end

    it "passes the chosen image model through as -m" do
      helper.generate_image_with_grok(prompt: "test", operation: "generate",
                                      image_model: "grok-imagine-image-2.0", out_dir: "/job")
      expect(helper.last_command).to include("-m #{Shellwords.shellescape('grok-imagine-image-2.0')}")
    end

    it "omits -m entirely when no model is chosen so the script uses the provider default" do
      helper.generate_image_with_grok(prompt: "test", operation: "generate", out_dir: "/job")
      expect(helper.last_command).not_to include(" -m ")
      helper.generate_image_with_grok(prompt: "test", operation: "generate", image_model: "  ", out_dir: "/job")
      expect(helper.last_command).not_to include(" -m ")
    end

    it "escapes a model name rather than interpolating it raw" do
      helper.generate_image_with_grok(prompt: "test", operation: "generate",
                                      image_model: "evil; rm -rf /", out_dir: "/job")
      expect(helper.last_command).to include(Shellwords.shellescape("evil; rm -rf /"))
      expect(helper.last_command).not_to include("-m evil;")
    end

    it "escapes image filenames with spaces" do
      helper.generate_image_with_grok(
        prompt: "edit",
        operation: "edit",
        images: ["/data/my image (1).png"],
        out_dir: "/job"
      )
      expect(helper.last_command).to include(Shellwords.shellescape("/data/my image (1).png"))
    end

    it "prevents shell metacharacter injection in prompt" do
      dangerous_prompt = 'test; rm -rf / && echo "pwned"'
      helper.generate_image_with_grok(prompt: dangerous_prompt, operation: "generate", out_dir: "/job")
      # The command should NOT contain unescaped semicolons or &&
      escaped = Shellwords.shellescape(dangerous_prompt)
      expect(helper.last_command).to include(escaped)
    end

    it "handles backtick injection attempts" do
      helper.generate_image_with_grok(prompt: 'test `whoami`', operation: "generate", out_dir: "/job")
      expect(helper.last_command).to include(Shellwords.shellescape('test `whoami`'))
    end

    it "handles $() subshell injection attempts" do
      helper.generate_image_with_grok(prompt: 'test $(cat /etc/passwd)', operation: "generate", out_dir: "/job")
      expect(helper.last_command).to include(Shellwords.shellescape('test $(cat /etc/passwd)'))
    end
  end

  describe "#generate_image_with_openai" do
    it "escapes prompt parameter" do
      helper.generate_image_with_openai(
        operation: "generate", model: "gpt-image-2", prompt: 'a "test" prompt',
        out_dir: "/job"
      )
      expect(helper.last_command).to include(Shellwords.shellescape('a "test" prompt'))
    end

    it "escapes model parameter" do
      helper.generate_image_with_openai(
        operation: "generate", model: "gpt-image-2", prompt: "test",
        out_dir: "/job"
      )
      expect(helper.last_command).to include(Shellwords.shellescape("gpt-image-2"))
    end

    it "formats numeric parameters safely" do
      helper.generate_image_with_openai(
        operation: "generate", model: "m", prompt: "test", n: 2,
        out_dir: "/job"
      )
      expect(helper.last_command).to include("-n 2")
    end

    it "escapes image paths" do
      helper.generate_image_with_openai(
        operation: "edit", model: "m", prompt: "edit",
        images: ["file with spaces.png"],
        out_dir: "/job"
      )
      expect(helper.last_command).to include(Shellwords.shellescape("file with spaces.png"))
    end

    it "names the job folder to write in, and makes nothing without one" do
      helper.generate_image_with_openai(operation: "generate", model: "m", prompt: "test", out_dir: "/state/a b")
      expect(helper.last_command).to include("--out-dir #{Shellwords.shellescape('/state/a b')}")
      fresh = helper_class.new
      result = JSON.parse(fresh.generate_image_with_openai(operation: "generate", model: "m", prompt: "test"))
      expect(result).to include("success" => false)
      expect(fresh.last_command).to be_nil
      expect(JSON.parse(fresh.generate_image_with_grok(prompt: "test"))).to include("success" => false)
      expect(fresh.last_command).to be_nil
    end
  end

  describe "#generate_video_with_grok_imagine" do
    before do
      allow(Monadic::Workbench::ChatOutput).to receive(:run_folder)
        .and_return({ path: "/data/conversations/c/artifacts/j_1", relative: "conversations/c/artifacts/j_1" })
      allow(Monadic::Workbench::ChatOutput).to receive(:take).and_return(nil)
      allow(Monadic::Workbench::ChatOutput).to receive(:drop_if_empty)
    end

    it "makes nothing without a run folder" do
      allow(Monadic::Workbench::ChatOutput).to receive(:run_folder).and_return(nil)
      expect(JSON.parse(helper.generate_video_with_grok_imagine(prompt: "test"))).to include("success" => false)
      expect(helper.last_command).to be_nil
    end

    it "escapes prompt for video generation" do
      helper.generate_video_with_grok_imagine(prompt: 'a "cinematic" scene')
      expect(helper.last_command).to include(Shellwords.shellescape('a "cinematic" scene'))
    end

    it "formats numeric duration safely" do
      helper.generate_video_with_grok_imagine(prompt: "test", duration: 5)
      expect(helper.last_command).to include("5")
    end
  end

end
