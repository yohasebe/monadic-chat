require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../../apps/auto_forge/auto_forge"

RSpec.describe AutoForge::Orchestrator do
  let(:context) { {} }
  subject(:orchestrator) { described_class.new(context) }

  let(:spec) do
    {
      name: "TestApp",
      type: "utility",
      description: "Test description",
      features: ["A"]
    }
  end

  let(:html_content) do
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head><title>AutoForge</title></head>
        <body><h1>Example</h1></body>
      </html>
    HTML
  end

  let(:temp_root) { Dir.mktmpdir("autoforge_spec") }
  let(:project_path) { File.join(temp_root, "TestApp_123") }

  let(:generator_double) { instance_double("HtmlGenerator") }

  before do
    allow(AutoForge::Agents::HtmlGenerator)
      .to receive(:new)
      .and_return(generator_double)

    allow_any_instance_of(described_class)
      .to receive(:write_file_with_verification) do |_instance, path, content|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        { success: true, size: content.length }
      end

    allow_any_instance_of(described_class)
      .to receive(:apply_patch_safely)
      .and_return({ success: true, affected_files: ["index.html"] })
  end

  after do
    AutoForge::Utils::StateManager.clear_project(orchestrator.project_id) if orchestrator.project_id
    FileUtils.remove_entry_secure(temp_root) if Dir.exist?(temp_root)
  end

  it "reuses the existing project directory on subsequent runs" do
    allow(AutoForgeUtils).to receive(:create_project_directory) do |base_name, metadata|
      FileUtils.mkdir_p(project_path)
      { name: "TestApp_123", path: project_path, metadata: metadata || {} }
    end

    patch_text = <<~PATCH
      --- index.html
      +++ index.html
      @@
      -Example
      +Example Updated
    PATCH

    allow(generator_double).to receive(:generate)
      .and_return(
        { mode: :full, content: html_content },
        { mode: :patch, patch: patch_text }
      )

    result1 = orchestrator.forge_project(spec)

    expect(result1[:success]).to be true
    expect(result1[:project_path]).to eq(project_path)
    expect(context.dig(:auto_forge, :project_path)).to eq(project_path)

    expect(AutoForgeUtils).not_to receive(:create_project_directory)

    result2 = orchestrator.forge_project(spec)
    expect(result2[:project_path]).to eq(project_path)
  end

  it "creates a new project when reset flag is provided" do
    created_paths = []
    allow(AutoForgeUtils).to receive(:create_project_directory) do |base_name, metadata|
      dir = File.join(temp_root, "#{base_name}_#{created_paths.size}")
      FileUtils.mkdir_p(dir)
      created_paths << dir
      { name: File.basename(dir), path: dir, metadata: metadata || {} }
    end

    allow(generator_double).to receive(:generate)
      .and_return({ mode: :full, content: html_content })

    result1 = orchestrator.forge_project(spec)
    expect(result1[:project_path]).to eq(created_paths[0])

    spec_with_reset = spec.merge(reset: true)
    result2 = orchestrator.forge_project(spec_with_reset)
    expect(result2[:project_path]).to eq(created_paths[1])
  end
end
