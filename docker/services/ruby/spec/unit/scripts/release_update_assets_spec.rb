# frozen_string_literal: true

require "spec_helper"
require "rake"
require "open3"
require "tmpdir"

# rake release:update_assets, run from rakelib/release.rake with gh replaced.
RSpec.describe "release:update_assets" do
  let(:root) { File.expand_path("../../../../../..", __dir__) }
  let(:main) { TOPLEVEL_BINDING.receiver }
  let(:status_ok) { instance_double(Process::Status, success?: true) }

  around do |example|
    Dir.mktmpdir do |home|
      @home = home
      example.run
    end
  end

  before do
    allow(Dir).to receive(:home).and_return(@home)
    Rake.application = Rake::Application.new
    %w[version release].each { |f| Rake.application.rake_require(f, [File.join(root, "rakelib")], []) }
    allow($stdin).to receive(:gets).and_return("y\n")
    allow(main).to receive(:puts)
    allow(main).to receive(:print)
  end

  def run_task(version, pattern)
    Rake::Task["release:update_assets"].invoke(version, pattern)
  end

  def stub_gh(body: "Notes", upload_ok: true)
    calls = []
    allow(main).to receive(:system) do |*args, **|
      calls << args
      args[0, 3] == ["gh", "release", "upload"] ? upload_ok : true
    end
    edited = nil
    allow(Open3).to receive(:capture3) do |*args|
      calls << args
      if args.include?("edit")
        edited = File.read(args.last)
        ["", "", status_ok]
      elsif args.include?("body")
        [edited || body, "", status_ok]
      else
        ['{"assets":[]}', "", status_ok]
      end
    end
    [calls, -> { edited }]
  end

  it "uploads without a shell and records the replacement in the release notes" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("app.zip", "x")
        calls, edited = stub_gh
        run_task("1.0.0-beta.44", "app.zip")
        expect(calls).to include(["gh", "release", "upload", "v1.0.0-beta.44", "--clobber", "--", File.expand_path("app.zip")])
        expect(edited.call).to match(/\ANotes\n\n- Release assets replaced on \d{4}-\d{2}-\d{2}: app\.zip\n\z/)
      end
    end
  end

  it "stops without touching the notes when the upload fails" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("app.zip", "x")
        _calls, edited = stub_gh(upload_ok: false)
        expect { run_task("1.0.0-beta.44", "app.zip") }.to raise_error(SystemExit)
        expect(edited.call).to be_nil
      end
    end
  end

  it "refuses a file name with shell or Markdown meaning before uploading anything" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("$(echo x).zip", "x")
        calls, = stub_gh
        expect { run_task("1.0.0-beta.44", "*.zip") }.to raise_error(SystemExit)
        expect(calls.none? { |c| c.include?("upload") }).to be true
      end
    end
  end

  it "refuses a file name that a command would read as an option" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("app.zip", "x")
        File.write("--help", "x")
        calls, = stub_gh
        expect { run_task("1.0.0-beta.44", "app.zip --help") }.to raise_error(SystemExit)
        expect(calls.none? { |c| c.include?("upload") }).to be true
      end
    end
  end

  it "stops when the notes do not read back as written" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("app.zip", "x")
        stub_gh
        allow(Open3).to receive(:capture3) do |*args|
          if args.include?("edit") then ["", "", status_ok]
          elsif args.include?("body") then ["Notes", "", status_ok]
          else ['{"assets":[]}', "", status_ok]
          end
        end
        expect { run_task("1.0.0-beta.44", "app.zip") }.to raise_error(SystemExit)
      end
    end
  end

  it "refuses something that is not a version" do
    stub_gh
    expect { run_task("1.0.0; rm -rf x", "app.zip") }.to raise_error(SystemExit)
  end
end
