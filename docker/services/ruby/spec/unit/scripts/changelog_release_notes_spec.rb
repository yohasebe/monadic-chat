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

  let(:note_maker) do
    source = File.read(File.join(root, "rakelib/release.rake"))
    method_source = source[/  def asset_replacement_note\(files, time\).*?\n  end\n/m]
    Object.new.tap { |o| o.instance_eval(method_source.sub("  def", "def")) }
  end

  it "records a replacement of release assets with the date and the file names" do
    note = note_maker.asset_replacement_note(["dist/b.dmg", "dist/a.zip"], Time.new(2026, 10, 17, 9, 0, 0))
    expect(note).to eq("- Release assets replaced on 2026-10-17: a.zip, b.dmg")
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

  it "gives a release only its own entry, not one whose version merely starts the same" do
    log = "- [October, 2026] 1.0.0-beta.2\n  - New\n    - Beta item\n\n- [October 22, 2024] 1.0.0 - First Stable Release\n  - New\n    - Stable item\n"
    notes = notes_for(log, "1.0.0")
    expect(notes).to include("Stable item")
    expect(notes).not_to include("Beta item")
  end

  it "ends an entry at the next entry, also one with a day or without a version" do
    log = "- [February, 2026] 1.0.0-beta.7\n  - Fixed\n    - Seven\n\n- [November 15, 2024] Recent Updates\n  - New\n    - Later\n"
    notes = notes_for(log, "1.0.0-beta.7")
    expect(notes).to include("Seven")
    expect(notes).not_to include("Later")
  end

  it "gives each version of the project's changelog the items under its own heading" do
    log = File.read(File.join(root, "CHANGELOG.md"))
    entries = log.split(/^(?=- \[)/)
    versions = entries.filter_map { |e| e[/\A- \[[\w\s,]+\] (\d+\.\d+\.\d+(?:-[\w.]+)?)/, 1] }.tally
    expect(versions).not_to be_empty
    versions.each do |version, count|
      next if count > 1 # a version with two headings is not told apart by version alone

      own = entries.find { |e| e.start_with?("- [") && e[/\A- \[[\w\s,]+\] (\S+)/, 1] == version }
      items = own.lines.drop(1).map(&:strip).reject(&:empty?).map { |l| l.delete_prefix("- ") }
      notes = notes_for(log, version)
      items.each { |item| expect(notes).to include(item), "#{version}: #{item[0, 60]}" }
      expect(notes).not_to match(/\n\n\n/)
    end
  end
end
