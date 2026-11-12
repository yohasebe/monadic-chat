# frozen_string_literal: true

require 'spec_helper'

# The apps whose code keeps what it makes in the chat's folder: each of
# their MDSLs turns it on, and none tells the model to embed a generated
# file in its reply.
RSpec.describe 'apps whose code output stays in the chat folder' do
  apps_dir = File.expand_path('../../../apps', __dir__)

  %w[research_assistant].each do |app|
    files = Dir.glob(File.join(apps_dir, app, '*.mdsl')).sort

    it "#{app}: every provider runs its code in the chat's folder" do
      expect(files).not_to be_empty
      files.each do |file|
        expect(File.read(file)).to match(/^\s*code_runs_in_chat_folder true$/), file
      end
    end

    it "#{app}: no provider embeds a generated file in the reply" do
      files.each do |file|
        text = File.read(file)
        expect(text).not_to include('<img src="/data/FILENAME"'), file
        expect(text).not_to include('<a href="/data/FILENAME"'), file
        expect(text).to include('shown on the work screen'), file
      end
    end
  end
end
