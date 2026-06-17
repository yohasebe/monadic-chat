# frozen_string_literal: true

# Regression guard for the Workflow Viewer graph data computed from REAL app
# settings. The unit specs in api_routes_spec.rb exercise the helpers with
# SYNTHETIC symbol-keyed inputs; production app settings are stored with STRING
# keys (e.g. settings["image_generation"] == "upload_only", settings[:image_generation] == nil).
# The image-generation/video-generation fix relies on the helpers' symbol→string
# fallback. This spec loads the actual apps and locks the end-to-end graph shape
# so a future change that only handles symbol keys (or rewires api_routes) is
# caught here even though the symbol-keyed unit tests would still pass.

require 'spec_helper'
require_relative '../../../lib/monadic/utils/workflow_viewer_helpers'

RSpec.describe 'Workflow Viewer graph data from real app settings' do
  WV = Monadic::Utils::WorkflowViewerHelpers

  before(:all) { TestAppLoader.load_all_apps }

  # Mirror of the api_routes.rb /api/app/:name/graph computation so the test
  # documents and locks the full end-to-end output/input shape (not just the
  # helpers in isolation).
  def output_types(s)
    out = ["text"]
    out << "image" if WV.wv_generates_image?(s)
    out << "video" if s[:video_generation] || s["video_generation"]
    out << "audio" if s[:auto_speech] || s["auto_speech"]
    out
  end

  def input_types(s)
    inp = ["text"]
    inp << "image" if s[:image] || s["image"] || WV.wv_accepts_image_upload?(s)
    inp
  end

  def settings_for(name)
    skip "#{name} not loaded" unless defined?(APPS) && APPS[name]
    APPS[name].settings
  end

  context 'image upload-only apps (image-to-X input, NOT image generators)' do
    it 'Music Generator: no image output, no image-generation feature, image input present' do
      s = settings_for('MusicGeneratorGemini')
      expect(WV.wv_generates_image?(s)).to be false
      expect(WV.wv_accepts_image_upload?(s)).to be true
      expect(WV.wv_extract_features(s)['image_generation']).to be false
      expect(output_types(s)).not_to include('image')
      expect(input_types(s)).to include('image')
    end

    %w[VideoGeneratorGemini VideoGeneratorGrok].each do |name|
      it "#{name}: video output + video-generation feature, image input, NOT image generation" do
        s = settings_for(name)
        expect(WV.wv_generates_image?(s)).to be false
        expect(WV.wv_accepts_image_upload?(s)).to be true
        feats = WV.wv_extract_features(s)
        expect(feats['image_generation']).to be false
        expect(feats['video_generation']).to be true
        expect(output_types(s)).to include('video')
        expect(output_types(s)).not_to include('image')
        expect(input_types(s)).to include('image')
      end
    end
  end

  context 'real image generators (declare image_generation false; artifact via tool)' do
    %w[ImageGeneratorGemini ImageGeneratorOpenAI].each do |name|
      it "#{name}: not flagged as image-generation feature, no image input from upload_only" do
        s = settings_for(name)
        expect(WV.wv_generates_image?(s)).to be false
        expect(WV.wv_accepts_image_upload?(s)).to be false
        expect(WV.wv_extract_features(s)['image_generation']).to be false
      end
    end
  end
end
