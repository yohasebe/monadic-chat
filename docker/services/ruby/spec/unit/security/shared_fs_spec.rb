# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require_relative "../../../lib/monadic/utils/shared_path_guard"

# Writes into the shared folder never reach a file outside it, even when a
# folder on the way is swapped for a link while the server works: the other
# program can do that at any moment, so each case swaps at a fixed point in
# the operation and checks that the file outside kept its bytes, mode and
# existence.
RSpec.describe Monadic::Utils::SharedFs do
  let(:guard) { Monadic::Utils::SharedPathGuard }

  around do |example|
    Dir.mktmpdir("shared-fs") do |dir|
      @root = File.join(dir, "data")
      @outside = File.join(dir, "outside")
      FileUtils.mkdir_p([File.join(@root, "work"), @outside])
      @secret = File.join(@outside, "report.txt")
      File.write(@secret, "SECRET")
      File.chmod(0o600, @secret)
      example.run
    end
  end

  before { allow(Monadic::Utils::Environment).to receive(:data_path).and_return(@root) }

  def outside_unchanged
    expect(File.binread(@secret)).to eq("SECRET")
    expect(File.stat(@secret).mode & 0o777).to eq(0o600)
    expect(Dir.children(@outside)).to eq(["report.txt"])
  end

  # Moves work/ away and puts a link to the outside folder in its place.
  def swap_work_for_link
    File.rename(File.join(@root, "work"), File.join(@root, "moved"))
    File.symlink(@outside, File.join(@root, "work"))
  end

  # Content that swaps the folder when the server starts reading it, after
  # the folder was opened and the temporary file made.
  def swapping_content(text = "NEW")
    io = StringIO.new(text)
    swapped = false
    io.define_singleton_method(:read) do |*args|
      unless swapped
        swapped = true
        File.rename(File.join(File.dirname(@secret), "..", "data", "work"), File.join(File.dirname(@secret), "..", "data", "moved"))
        File.symlink(File.dirname(@secret), File.join(File.dirname(@secret), "..", "data", "work"))
      end
      super(*args)
    end
    io.instance_variable_set(:@secret, @secret)
    io
  end

  describe "write_file!" do
    it "writes a new file and replaces an old one, keeping its mode" do
      path = File.join(@root, "work", "report.txt")
      guard.write_file!(path, "one")
      expect(File.stat(path).mode & 0o777).to eq(0o644)
      File.chmod(0o600, path)
      guard.write_file!(path, "two")
      expect(File.read(path)).to eq("two")
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(Dir.children(File.join(@root, "work"))).to eq(["report.txt"])
    end

    it "does not change a file that has another name too (a hard link)" do
      path = File.join(@root, "work", "report.txt")
      File.write(path, "kept")
      File.link(path, File.join(@root, "other.txt"))
      guard.write_file!(path, "new")
      expect(File.read(File.join(@root, "other.txt"))).to eq("kept")
    end

    it "refuses a link in the file's place, and a folder on the way that is a link out" do
      File.symlink(@secret, File.join(@root, "work", "report.txt"))
      expect { guard.write_file!(File.join(@root, "work", "report.txt"), "NEW") }.to raise_error(guard::InvalidPath)
      FileUtils.rm_rf(File.join(@root, "work"))
      File.symlink(@outside, File.join(@root, "work"))
      expect { guard.write_file!(File.join(@root, "work", "report.txt"), "NEW") }.to raise_error(guard::InvalidPath)
      outside_unchanged
    end

    it "keeps writing in the folder it opened when that folder is swapped for a link meanwhile" do
      guard.write_file!(File.join(@root, "work", "report.txt"), swapping_content)
      outside_unchanged
      expect(File.read(File.join(@root, "moved", "report.txt"))).to eq("NEW")
    end

    it "keeps appending to the file it opened when the folder is swapped meanwhile" do
      File.write(File.join(@root, "work", "report.txt"), "old ")
      guard.write_file!(File.join(@root, "work", "report.txt"), swapping_content, mode: "a")
      outside_unchanged
      expect(File.read(File.join(@root, "moved", "report.txt"))).to eq("old NEW")
    end

    it "appends nothing to a link, a FIFO, or a file with another name" do
      File.symlink(@secret, File.join(@root, "work", "a.txt"))
      expect { guard.write_file!(File.join(@root, "work", "a.txt"), "X", mode: "a") }.to raise_error(guard::InvalidPath)
      File.mkfifo(File.join(@root, "work", "pipe"))
      expect { guard.write_file!(File.join(@root, "work", "pipe"), "X", mode: "a") }.to raise_error(guard::InvalidPath)
      File.write(File.join(@root, "work", "b.txt"), "b")
      File.link(File.join(@root, "work", "b.txt"), File.join(@root, "b2.txt"))
      expect { guard.write_file!(File.join(@root, "work", "b.txt"), "X", mode: "a") }.to raise_error(guard::InvalidPath)
      expect(File.read(File.join(@root, "b2.txt"))).to eq("b")
      outside_unchanged
    end

    it "puts a file in place only when nothing has its name, with replace: false" do
      path = File.join(@root, "work", "report.txt")
      File.write(path, "first")
      expect { guard.write_file!(path, "second", replace: false) }.to raise_error(Errno::EEXIST)
      expect(File.read(path)).to eq("first")
      expect(Dir.children(File.join(@root, "work"))).to eq(["report.txt"])
    end

    it "sets the mode on the file it wrote, not through a link" do
      guard.write_file!(File.join(@root, "work", "run.sh"), "echo", perm: 0o755)
      expect(File.stat(File.join(@root, "work", "run.sh")).mode & 0o777).to eq(0o755)
    end

    it "never opens a file already at its temporary name" do
      allow(SecureRandom).to receive(:hex).and_return("0" * 16)
      File.symlink(@secret, File.join(@root, "work", ".report.txt.#{'0' * 16}.tmp"))
      expect { guard.write_file!(File.join(@root, "work", "report.txt"), "NEW") }.to raise_error(Errno::EEXIST)
      outside_unchanged
    end

    it "refuses a plain file where a folder on the way should be" do
      File.write(File.join(@root, "notdir"), "x")
      expect { guard.write_file!(File.join(@root, "notdir", "report.txt"), "NEW") }.to raise_error(guard::InvalidPath)
      expect { guard.mkdir_p!(File.join(@root, "notdir", "sub")) }.to raise_error(guard::InvalidPath)
    end

    it "writes nothing where the server loads code from, by any name or path" do
      FileUtils.mkdir_p(File.join(@root, "ordinary"))
      File.symlink(File.join(@root, "ordinary"), File.join(@root, "helpers"))
      expect { guard.write_file!(File.join(@root, "ordinary", "x.rb"), "puts 1") }.to raise_error(guard::InvalidPath)
      expect { guard.write_file!(File.join(@root, "Helpers", "x.rb"), "puts 1") }.to raise_error(guard::InvalidPath)
      FileUtils.mkdir_p(File.join(@root, "apps"))
      expect { guard.write_file!(File.join(@root, "apps", "x.rb"), "puts 1") }.to raise_error(guard::InvalidPath)
      expect(Dir.children(File.join(@root, "ordinary"))).to be_empty
    end

    it "makes a file it appends to with the mode asked for" do
      guard.write_file!(File.join(@root, "work", "log.txt"), "a", mode: "a")
      expect(File.stat(File.join(@root, "work", "log.txt")).mode & 0o777).to eq(0o644)
    end

    it "leaves no temporary file when writing fails" do
      failing = StringIO.new("x")
      failing.define_singleton_method(:read) { |*| raise IOError, "stopped" }
      expect { guard.write_file!(File.join(@root, "work", "report.txt"), failing) }.to raise_error(IOError)
      expect(Dir.children(File.join(@root, "work"))).to be_empty
    end
  end

  describe "read_file! and copy_file!" do
    it "reads a plain file, and refuses a link or a FIFO without waiting" do
      File.write(File.join(@root, "work", "in.txt"), "hello")
      expect(guard.read_file!(File.join(@root, "work", "in.txt"), &:read)).to eq("hello")
      File.symlink(@secret, File.join(@root, "work", "link.txt"))
      expect { guard.read_file!(File.join(@root, "work", "link.txt"), &:read) }.to raise_error(guard::InvalidPath)
      File.mkfifo(File.join(@root, "work", "pipe"))
      expect { guard.read_file!(File.join(@root, "work", "pipe"), &:read) }.to raise_error(guard::InvalidPath)
    end

    it "copies nothing from outside through a link" do
      File.symlink(@secret, File.join(@root, "work", "index.html"))
      expect { guard.copy_file!(File.join(@root, "work", "index.html"), File.join(@root, "work", "backup")) }
        .to raise_error(guard::InvalidPath)
      expect(File.exist?(File.join(@root, "work", "backup"))).to be(false)
    end
  end

  describe "delete_file!" do
    it "removes in the folder it opened when that folder is swapped for a link meanwhile" do
      File.write(File.join(@root, "work", "report.txt"), "mine")
      allow(described_class).to receive(:unlink).and_wrap_original do |original, dir, name|
        swap_work_for_link
        original.call(dir, name)
      end
      expect(guard.delete_file!(File.join(@root, "work", "report.txt"))).to be(true)
      outside_unchanged
      expect(File.exist?(File.join(@root, "moved", "report.txt"))).to be(false)
    end

    it "removes a link itself, never a folder, and nothing through a folder that is a link" do
      File.symlink(@secret, File.join(@root, "work", "l"))
      guard.delete_file!(File.join(@root, "work", "l"))
      FileUtils.mkdir_p(File.join(@root, "work", "d"))
      expect { guard.delete_file!(File.join(@root, "work", "d")) }.to raise_error(SystemCallError)
      FileUtils.rm_rf(File.join(@root, "work"))
      File.symlink(@outside, File.join(@root, "work"))
      expect { guard.delete_file!(File.join(@root, "work", "report.txt")) }.to raise_error(guard::InvalidPath)
      outside_unchanged
    end
  end

  describe "mkdir_p! and rename_file!" do
    it "makes folders, but none through a link on the way" do
      guard.mkdir_p!(File.join(@root, "a", "b", "c"))
      expect(File.directory?(File.join(@root, "a", "b", "c"))).to be(true)
      File.symlink(@outside, File.join(@root, "a", "x"))
      expect { guard.mkdir_p!(File.join(@root, "a", "x", "y")) }.to raise_error(guard::InvalidPath)
      outside_unchanged
    end

    it "makes nothing outside when a folder on the way is swapped for a link as it is made" do
      allow(described_class).to receive(:open_child_dir).and_wrap_original do |original, dir, part, create:|
        swap_work_for_link if part == "work" && File.directory?(File.join(@root, "work")) && !File.symlink?(File.join(@root, "work"))
        original.call(dir, part, create: create)
      end
      expect { guard.mkdir_p!(File.join(@root, "work", "new")) }.to raise_error(guard::InvalidPath)
      outside_unchanged
    end

    it "renames within the shared folder, not into a folder that is a link" do
      File.write(File.join(@root, "work", "a.txt"), "a")
      guard.rename_file!(File.join(@root, "work", "a.txt"), File.join(@root, "work", "b.txt"))
      expect(File.read(File.join(@root, "work", "b.txt"))).to eq("a")
      File.symlink(@outside, File.join(@root, "out"))
      expect { guard.rename_file!(File.join(@root, "work", "b.txt"), File.join(@root, "out", "report.txt")) }
        .to raise_error(guard::InvalidPath)
      outside_unchanged
    end

    it "moves no folder, and nothing named or placed as a code folder" do
      FileUtils.mkdir_p(File.join(@root, "apps"))
      File.write(File.join(@root, "apps", "x.rb"), "kept")
      expect { guard.rename_file!(File.join(@root, "apps"), File.join(@root, "moved")) }.to raise_error(guard::InvalidPath)
      expect { guard.rename_file!(File.join(@root, "work"), File.join(@root, "w2")) }.to raise_error(guard::InvalidPath)
      File.write(File.join(@root, "work", "a.txt"), "a")
      expect { guard.rename_file!(File.join(@root, "work", "a.txt"), File.join(@root, "Helpers")) }.to raise_error(guard::InvalidPath)
      expect { guard.write_file!(File.join(@root, "scripts"), "x") }.to raise_error(guard::InvalidPath)
      File.symlink(File.join(@root, "work"), File.join(@root, "services"))
      expect { guard.delete_file!(File.join(@root, "services")) }.to raise_error(guard::InvalidPath)
      expect(File.symlink?(File.join(@root, "services"))).to be(true)
      expect(File.read(File.join(@root, "apps", "x.rb"))).to eq("kept")
    end

    it "refuses the real folder behind a code folder's link as a name too" do
      FileUtils.mkdir_p(File.join(@root, "ordinary"))
      File.symlink(File.join(@root, "ordinary"), File.join(@root, "helpers"))
      File.write(File.join(@root, "work", "a.txt"), "a")
      expect { guard.rename_file!(File.join(@root, "work", "a.txt"), File.join(@root, "ordinary")) }.to raise_error(guard::InvalidPath)
      expect(File.directory?(File.join(@root, "ordinary"))).to be(true)
    end
  end

  describe "remove_tree!" do
    it "removes a folder and what is in it, and a link inside it as a link" do
      FileUtils.mkdir_p(File.join(@root, "work", "project", "sub"))
      File.write(File.join(@root, "work", "project", "sub", "a.txt"), "a")
      File.symlink(@outside, File.join(@root, "work", "project", "out"))
      File.symlink(@secret, File.join(@root, "work", "project", "sub", "secret"))
      guard.remove_tree!(File.join(@root, "work", "project"))
      expect(File.exist?(File.join(@root, "work", "project"))).to be(false)
      outside_unchanged
    end

    it "removes nothing outside when a folder inside is swapped for a link while it runs" do
      FileUtils.mkdir_p(File.join(@root, "work", "project", "sub"))
      File.write(File.join(@root, "work", "project", "sub", "report.txt"), "mine")
      swapped = false
      allow(Dir).to receive(:children).and_wrap_original do |original, path|
        names = original.call(path)
        if !swapped && path.end_with?("/sub")
          swapped = true
          File.rename(path, "#{path}.moved")
          File.symlink(@outside, path)
        end
        names
      end
      guard.remove_tree!(File.join(@root, "work", "project")) rescue nil
      outside_unchanged
    end

    it "removes nothing of a code folder's real place inside it, however deep" do
      FileUtils.mkdir_p(File.join(@root, "ordinary", "deep", "code"))
      File.write(File.join(@root, "ordinary", "deep", "code", "sample.rb"), "kept")
      File.symlink(File.join(@root, "ordinary", "deep", "code"), File.join(@root, "helpers"))
      expect { guard.remove_tree!(File.join(@root, "ordinary")) }.to raise_error(guard::InvalidPath)
      expect(File.read(File.join(@root, "ordinary", "deep", "code", "sample.rb"))).to eq("kept")
    end

    it "refuses a code folder or a project behind a link" do
      FileUtils.mkdir_p(File.join(@root, "apps"))
      expect { guard.remove_tree!(File.join(@root, "apps")) }.to raise_error(guard::InvalidPath)
      File.symlink(@outside, File.join(@root, "work", "linked"))
      guard.remove_tree!(File.join(@root, "work", "linked"))
      expect(File.exist?(File.join(@root, "work", "linked"))).to be(false)
      outside_unchanged
    end
  end

  describe "descriptors and failures" do
    it "opens nothing a child process would inherit" do
      File.write(File.join(@root, "work", "in.txt"), "x")
      expect(guard.read_file!(File.join(@root, "work", "in.txt"), &:close_on_exec?)).to be(true)
      described_class.in_dir(File.realpath(@root), ["work"]) { |dir| expect(dir.close_on_exec?).to be(true) }
    end

    it "does not hide why writing failed when its temporary file is already gone" do
      failing = StringIO.new("x")
      failing.define_singleton_method(:read) do |*|
        Dir.glob(File.join(File.dirname(@secret), "..", "data", "work", ".*.tmp")).each { |f| File.delete(f) }
        raise IOError, "original failure"
      end
      failing.instance_variable_set(:@secret, @secret)
      expect { guard.write_file!(File.join(@root, "work", "report.txt"), failing) }.to raise_error(IOError, "original failure")
    end

    it "reports a file put in place as written, even when tidying its temporary name fails" do
      original = described_class.method(:call!)
      allow(described_class).to receive(:call!) do |func, *args|
        raise Errno::EIO if func == :unlinkat

        original.call(func, *args)
      end
      guard.write_file!(File.join(@root, "work", "new.txt"), "done", replace: false)
      expect(File.read(File.join(@root, "work", "new.txt"))).to eq("done")
    end

    it "takes only the modes it knows" do
      expect { guard.write_file!(File.join(@root, "work", "x"), "x", mode: "r+") }.to raise_error(ArgumentError)
      expect { guard.write_file!(File.join(@root, "work", "x"), "x", mode: "a", replace: false) }.to raise_error(ArgumentError)
    end
  end
end
