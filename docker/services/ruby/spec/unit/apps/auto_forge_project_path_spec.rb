# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../../apps/auto_forge/auto_forge"

# A project path given by the model is used only inside AutoForge's own
# folder: elsewhere in the shared folder (custom apps and helpers among
# them) a generated file would be code the server loads.
RSpec.describe AutoForge::Orchestrator, "project path" do
  subject(:orchestrator) { described_class.new({}) }

  around do |example|
    Dir.mktmpdir("autoforge-path-") do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  before do
    allow(AutoForge::Utils::PathConfig).to receive(:project_base_path).and_return(File.join(@root, "auto_forge"))
    %w[auto_forge/MyApp_1 helpers apps/x/helpers ordinary].each { |d| FileUtils.mkdir_p(File.join(@root, d)) }
    File.symlink(File.join(@root, "helpers"), File.join(@root, "auto_forge", "Linked"))
  end

  def context_for(path)
    orchestrator.send(:existing_project_context, { name: "MyApp", project_path: path })
  end

  it "takes a project under AutoForge's folder" do
    expect(context_for(File.join(@root, "auto_forge", "MyApp_1"))).to include(existing: true)
  end

  it "refuses a folder elsewhere in the shared folder" do
    %w[helpers apps/x/helpers ordinary auto_forge].each do |dir|
      expect(context_for(File.join(@root, dir))).to be_nil, "#{dir} was taken"
    end
  end

  it "refuses a link under AutoForge's folder that points elsewhere" do
    expect(context_for(File.join(@root, "auto_forge", "Linked"))).to be_nil
  end
end
