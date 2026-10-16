# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The GitHub release notes are cut from CHANGELOG.md by
# extract_changelog_entry in rakelib/release.rake; this runs that method.
RSpec.describe "Release notes from the changelog" do
  let(:root) { File.expand_path("../../../../../..", __dir__) }

  let(:extractor) do
    source = File.read(File.join(root, "rakelib/release.rake"))
    method_source = source[/  def extract_changelog_entry\(version\).*?\n  end\n/m]
    Object.new.tap { |o| o.instance_eval(method_source.sub("  def", "def")) }
  end

  def notes_for(changelog, version)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "CHANGELOG.md"), changelog)
      Dir.chdir(dir) { extractor.extract_changelog_entry(version) }
    end
  end

  let(:changelog) do
    <<~MD
      - [October, 2026] 2.0.0
        - Security
          - **Do this**
          - Fixed a thing
        - Fixed
          - Something works

      - [September, 2026] 1.9.0
        - An old-style item
    MD
  end

  it "turns the groups into headings with their items listed under them" do
    notes = notes_for(changelog, "2.0.0")
    expect(notes).to start_with("## Monadic Chat 2.0.0\n\n### Security\n\n- **Do this**\n- Fixed a thing\n\n### Fixed\n\n- Something works\n")
    expect(notes).not_to include("1.9.0")
  end

  it "keeps an entry in the older form as a list" do
    expect(notes_for(changelog, "1.9.0")).to start_with("## Monadic Chat 1.9.0\n\n- An old-style item\n")
  end

  it "finds every entry of the project's changelog" do
    versions = File.read(File.join(root, "CHANGELOG.md")).scan(/^- \[[\w\s,]+\] (\d+\.\d+\.\d+(?:-[\w.]+)?)/).flatten
    expect(versions).not_to be_empty
    versions.first(5).each { |v| expect(notes_for(File.read(File.join(root, "CHANGELOG.md")), v)).to include("## Monadic Chat #{v}") }
  end
end
