# frozen_string_literal: true

require_relative '../spec_helper'
require_relative "../../lib/monadic/adapters/file_analysis_helper"

RSpec.describe MonadicHelper do
  # Create a test class that includes the MonadicHelper module
  let(:test_class) do
    Class.new do
      include MonadicHelper
      
      attr_accessor :settings
      
      def initialize
        @settings = {
          "model" => "gpt-4.1",
          :model => "gpt-4.1"
        }
      end
      
      # Mock send_command method
      def send_command(command:, container:)
        {
          "status" => "success",
          "response" => "Mock analysis result",
          "command" => command,
          "container" => container
        }
      end
      
      # Mock check_vision_capability method
      def check_vision_capability(model)
        return "gpt-4.1" if ["gpt-4.1", "gpt-4o"].include?(model)
        nil
      end
    end
  end
  
  let(:helper) { test_class.new }

  describe "#analyze_image" do
    it "calls send_command with correct parameters" do
      expect(helper).to receive(:send_command).with(
        command: match(/image_query\.rb.*test message.*\/path\/to\/image\.jpg.*gpt-4\.1/),
        container: "ruby"
      )
      
      helper.analyze_image(
        message: "test message",
        image_path: "/path/to/image.jpg",
        model: "gpt-4.1"
      )
    end
    
    it "escapes quotes in message" do
      expect(helper).to receive(:send_command).with(
        command: match(/image_query\.rb.*message with \\\"quotes\\\"/),
        container: "ruby"
      )
      
      helper.analyze_image(
        message: 'message with "quotes"',
        image_path: "/path/to/image.jpg"
      )
    end
    
    it "uses model from settings when not provided" do
      expect(helper).to receive(:send_command).with(
        command: match(/gpt-4\.1/),
        container: "ruby"
      )
      
      helper.analyze_image(
        message: "test message",
        image_path: "/path/to/image.jpg"
      )
    end
    
    it "checks vision capability and falls back to default model" do
      # In actual implementation, model parameter is ignored and settings["model"] is used
      expect(helper).to receive(:check_vision_capability).with("gpt-4.1").and_return(nil)
      expect(helper).to receive(:send_command).with(
        command: match(/gpt-4\.1/),
        container: "ruby"
      )
      
      helper.analyze_image(
        message: "test message",
        image_path: "/path/to/image.jpg",
        model: "invalid-model"  # This parameter is actually ignored by the implementation
      )
    end
    
    it "returns the result from send_command" do
      result = helper.analyze_image(
        message: "test message",
        image_path: "/path/to/image.jpg"
      )
      
      expect(result).to be_a(Hash)
      expect(result["status"]).to eq("success")
      expect(result["container"]).to eq("ruby")
    end
  end

  describe "#analyze_audio" do
    it "calls send_command with correct parameters" do
      expect(helper).to receive(:send_command).with(
        command: match(/stt_query\.rb.*\/path\/to\/audio\.mp3.*\.*json.*.*gpt-4o-transcribe/),
        container: "ruby"
      )
      
      helper.analyze_audio(
        audio: "/path/to/audio.mp3",
        model: "gpt-4o-transcribe"
      )
    end
    
    it "uses default model when not provided" do
      expect(helper).to receive(:send_command).with(
        command: match(/gpt-4o-transcribe/),
        container: "ruby"
      )
      
      helper.analyze_audio(audio: "/path/to/audio.mp3")
    end
    
    it "formats command correctly with all parameters" do
      expect(helper).to receive(:send_command) do |args|
        command = args[:command]
        expect(command).to include('stt_query.rb')
        expect(command).to include('"/path/to/audio.mp3"')
        expect(command).to include('"."')  # output directory
        expect(command).to include('"json"')  # format
        expect(command).to include('""')  # empty parameter
        expect(command).to include('"gpt-4o-transcribe"')  # model
        
        { "status" => "success" }
      end
      
      helper.analyze_audio(
        audio: "/path/to/audio.mp3",
        model: "gpt-4o-transcribe"
      )
    end
    
    it "returns the result from send_command" do
      result = helper.analyze_audio(audio: "/path/to/audio.mp3")
      
      expect(result).to be_a(Hash)
      expect(result["status"]).to eq("success")
      expect(result["container"]).to eq("ruby")
    end
  end
end