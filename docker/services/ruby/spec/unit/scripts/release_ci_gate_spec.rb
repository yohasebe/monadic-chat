require 'spec_helper'
require 'open3'
require 'rake'

# The release task's half of the CI gate. verify_ci_green.rb decides whether a
# commit passed; these helpers decide *which* commit that question is asked
# about, and whether the answer is still true at the moment of publishing.
#
# Both directions have gone wrong in this repository: a release built from one
# tree while a manifest described another, and a tag that resolved somewhere
# other than where the release was meant to land. A gate that checks a commit
# nobody publishes is not a gate.
RSpec.describe 'the release CI gate in rakelib/release.rake' do
  RAKE_FILE = File.expand_path('../../../../../../rakelib/release.rake', __dir__)

  let(:dev_sha) { 'd' * 40 }
  let(:release_sha) { 'ab12cd34' * 5 }
  let(:tree) { 't' * 40 }
  let(:tag) { 'v1.0.0-beta.36' }

  # Loaded into a module of its own rather than with `load`, which would define
  # these as private methods on Object for every other spec in the suite.
  def load_helpers
    source = File.read(RAKE_FILE)
    cut = source.index('# GitHub Release Management Tasks')
    raise 'helper section not found in release.rake' if cut.nil?

    mod = Module.new
    mod.module_eval(source[0...cut], RAKE_FILE, 1)
    Object.new.extend(mod)
  end

  let(:gate) { load_helpers }

  # `abort` raises SystemExit, which ends the whole RSpec process rather than
  # failing one example -- a broken gate would take the suite down with an
  # exit code and no named failure. Turn it into an ordinary failure.
  def without_aborting
    yield
  rescue SystemExit
    raise 'the gate aborted when it should have let the release through'
  end

  def stub_git(output, status: instance_double(Process::Status, success?: true))
    allow(Open3).to receive(:capture2).and_return([output, status])
  end

  def stub_resolution(commits: {}, trees: {})
    allow(gate).to receive(:git_commit_of) { |ref| commits[ref] }
    allow(gate).to receive(:git_tree_of) { |ref| trees[ref] }
  end

  describe 'choosing the commit whose CI is checked' do
    it 'refuses to run without a release commit' do
      expect { gate.verify_release_ci_green(nil) }.to raise_error(SystemExit)
        .and output(/third argument/).to_stderr
    end

    # `origin/dev` in a local clone is a tracking ref that can be behind, and
    # checking an older tree's green would report it as this release's.
    it 'asks the remote for the dev tip rather than the local tracking ref' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(commits: { release_sha => release_sha },
                      trees: { dev_sha => tree, release_sha => tree })
      allow(gate).to receive(:system).and_return(true)

      without_aborting { gate.verify_release_ci_green(release_sha) }
      expect(Open3).to have_received(:capture2).with('git', 'ls-remote', 'origin', 'refs/heads/dev')
    end

    it 'checks CI for the dev commit, not for the release commit' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(commits: { release_sha => release_sha },
                      trees: { dev_sha => tree, release_sha => tree })
      allow(gate).to receive(:system).and_return(true)

      without_aborting { gate.verify_release_ci_green(release_sha) }
      expect(gate).to have_received(:system).with('ruby', 'scripts/verify_ci_green.rb', dev_sha, 'dev')
    end

    # `gh release create --target main` is resolved by GitHub at publish time,
    # minutes after this check, so a name must become a SHA here.
    it 'returns the release commit resolved to a SHA, not the name it was given' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(commits: { 'main' => release_sha },
                      trees: { dev_sha => tree, release_sha => tree })
      allow(gate).to receive(:system).and_return(true)

      expect(without_aborting { gate.verify_release_ci_green('main') }).to eq([dev_sha, release_sha])
    end

    it 'takes the tree from the resolved commit rather than the name' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(commits: { 'main' => release_sha },
                      trees: { dev_sha => tree, release_sha => tree })
      allow(gate).to receive(:system).and_return(true)

      without_aborting { gate.verify_release_ci_green('main') }
      expect(gate).to have_received(:git_tree_of).with(release_sha)
      expect(gate).not_to have_received(:git_tree_of).with('main')
    end

    # Tree identity is the only thing tying the release commit to the commit
    # CI ran on, because commit-tree gives the release its own SHA.
    it 'refuses a release commit built from a different tree' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(commits: { release_sha => release_sha },
                      trees: { dev_sha => tree, release_sha => 'x' * 40 })

      expect { gate.verify_release_ci_green(release_sha) }.to raise_error(SystemExit)
        .and output(/not the tree CI ran against/).to_stderr
    end

    it 'refuses when CI did not pass' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(commits: { release_sha => release_sha },
                      trees: { dev_sha => tree, release_sha => tree })
      allow(gate).to receive(:system).and_return(false)

      expect { gate.verify_release_ci_green(release_sha) }.to raise_error(SystemExit)
        .and output(/nothing was published/).to_stderr
    end

    it 'refuses when the remote cannot be read' do
      stub_git('', status: instance_double(Process::Status, success?: false))
      expect { gate.verify_release_ci_green(release_sha) }.to raise_error(SystemExit)
        .and output(%r{cannot read origin/dev}).to_stderr
    end

    it 'refuses when origin has no dev branch' do
      stub_git('')
      expect { gate.verify_release_ci_green(release_sha) }.to raise_error(SystemExit)
        .and output(/no dev branch/).to_stderr
    end

    it 'refuses a release commit this clone cannot resolve' do
      stub_git("#{dev_sha}\trefs/heads/dev\n")
      stub_resolution(trees: { dev_sha => tree })
      expect { gate.verify_release_ci_green('nosuchref') }.to raise_error(SystemExit)
        .and output(/cannot be resolved to a commit/).to_stderr
    end
  end

  # Exercised against real git rather than a stub, because the bug these cover
  # was in the refspecs handed to `ls-remote`: asking only for refs/tags/<tag>
  # returns the tag OBJECT for an annotated tag and no peeled line at all, so
  # the peeling code never saw one and a correct release was refused.
  #
  # Deliberately NOT tagged :integration. That tag is how the unit job excludes
  # what needs Docker (`rspec spec/unit --tag '~integration'`), and these run
  # against a temporary local repository with no network and no containers.
  # Tagging them would have put the only test that catches this bug where CI
  # never looks.
  describe 'reading the tag from a real repository' do
    let(:repo) { @repo }

    before(:all) do
      require 'tmpdir'
      @dir = Dir.mktmpdir('release_gate_tags')
      @repo = File.join(@dir, 'work')
      origin = File.join(@dir, 'origin.git')
      system('git', 'init', '--quiet', '--bare', origin, out: File::NULL, err: File::NULL)
      system('git', 'init', '--quiet', @repo, out: File::NULL, err: File::NULL)
      Dir.chdir(@repo) do
        File.write('a', "x\n")
        %w[user.email t@example.invalid user.name tester].each_slice(2) do |k, v|
          system('git', 'config', k, v)
        end
        system('git', 'add', 'a', out: File::NULL)
        system('git', 'commit', '--quiet', '-m', 'one', out: File::NULL)
        system('git', 'remote', 'add', 'origin', origin)
        system('git', 'tag', '-a', 'v1.0.0-beta.36', '-m', 'annotated', out: File::NULL)
        system('git', 'tag', 'v1.0.0-beta.37', out: File::NULL)
        system('git', 'push', '--quiet', 'origin', '--tags', out: File::NULL, err: File::NULL)
      end
    end

    after(:all) { FileUtils.remove_entry(@dir) if @dir }

    def head_sha
      Dir.chdir(repo) { `git rev-parse HEAD`.strip }
    end

    def check(version, target)
      Dir.chdir(repo) do
        host = load_helpers
        allow(host).to receive(:system).and_return(true)
        host.verify_release_is_still_publishable(version, target, dev_sha)
      end
    end

    it 'accepts an annotated tag that peels to the release commit' do
      expect { without_aborting { check('1.0.0-beta.36', head_sha) } }.not_to raise_error
    end

    it 'accepts a lightweight tag on the release commit' do
      expect { without_aborting { check('1.0.0-beta.37', head_sha) } }.not_to raise_error
    end

    it 'refuses an annotated tag that peels somewhere else' do
      expect { check('1.0.0-beta.36', 'f' * 40) }.to raise_error(SystemExit)
        .and output(/points at/).to_stderr
    end

    it 'allows a tag that does not exist yet' do
      expect { without_aborting { check('9.9.9', head_sha) } }.not_to raise_error
    end
  end

  describe 'confirming just before publishing' do
    it 'refuses when the tag on origin points somewhere else' do
      stub_git("#{'e' * 40}\trefs/tags/#{tag}\n")

      expect { gate.verify_release_is_still_publishable('1.0.0-beta.36', release_sha, dev_sha) }
        .to raise_error(SystemExit).and output(/points at eeeeeeee, not the release commit/).to_stderr
    end

    # Four platforms take long enough for someone to re-run CI in the middle.
    it 'checks CI again, on the commit the first check settled on' do
      stub_git("#{release_sha}\trefs/tags/#{tag}\n")
      allow(gate).to receive(:system).and_return(false)

      expect { gate.verify_release_is_still_publishable('1.0.0-beta.36', release_sha, dev_sha) }
        .to raise_error(SystemExit).and output(/no longer green/).to_stderr
      expect(gate).to have_received(:system).with('ruby', 'scripts/verify_ci_green.rb', dev_sha, 'dev')
    end

    it 'refuses when the tag cannot be read' do
      stub_git('', status: instance_double(Process::Status, success?: false))
      expect { gate.verify_release_is_still_publishable('1.0.0-beta.36', release_sha, dev_sha) }
        .to raise_error(SystemExit).and output(/cannot read the v1.0.0-beta.36 tag/).to_stderr
    end
  end

  # Checking the helpers is not the same as checking that the task calls them.
  # Removing the pre-publish call and the draft's third argument left every
  # helper example passing, so the task itself is run here with its side
  # effects replaced.
  describe 'the release tasks as they actually run' do
    let(:published) { [] }
    let(:ci_results) { [true, true] }

    # Loads the whole file -- tasks included -- into a module that supplies the
    # helpers release.rake expects from elsewhere in rakelib, so nothing is
    # defined on Object and nothing reaches the network or the filesystem.
    def app_with_tasks
      Rake.application = Rake::Application.new
      host = Module.new
      host.extend(Rake::DSL)
      # The array itself, not a copy: an example sets the sequence with
      # `replace` after this hook has already handed it to the task.
      results = ci_results
      out = published
      host.define_singleton_method(:get_current_version) { '1.0.0-beta.36' }
      host.define_singleton_method(:escape_version_for_files) { |v| v }
      host.define_singleton_method(:find_build_files) { |pattern, *| ["dist/#{pattern}"] }
      host.define_singleton_method(:extract_changelog_entry) { |_v| 'notes' }
      host.define_singleton_method(:sh) { |cmd| out << cmd }
      host.define_singleton_method(:system) do |*args|
        args.include?('scripts/verify_ci_green.rb') ? results.shift : true
      end
      host.instance_eval(File.read(RAKE_FILE), RAKE_FILE, 1)
      [Rake.application, host]
    end

    # Only the Rake application swap belongs in `around`; rspec-mocks stubs
    # have to be set inside the example's own lifecycle.
    around do |example|
      previous = Rake.application
      example.run
    ensure
      Rake.application = previous
    end

    before do
      require File.expand_path('../../../../../../scripts/release_manifest_set', __dir__)
      @app, @host, = app_with_tasks
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with(/release_notes/, anything)
      allow(ReleaseManifestSet).to receive(:select).and_return([['dist/latest.yml'], nil])
    end

    def run(task, *args)
      stub_git("#{release_sha}\trefs/tags/#{tag}\n")
      allow(@host).to receive(:git_commit_of) { |ref| ref == 'HEAD' ? release_sha : ref }
      allow(@host).to receive(:git_tree_of).and_return(tree)
      @app[task].invoke(*args)
    end

    it 'publishes when CI is green at both checks' do
      without_aborting { run('release:github', '1.0.0-beta.36', 'true', release_sha) }
      expect(published.join).to include("gh release create #{tag}", "--target #{release_sha}")
    end

    # The whole point of the second check: green before a long build, red by
    # the time the release would be created.
    it 'does not publish when CI went red during the build' do
      ci_results.replace([true, false])
      expect { run('release:github', '1.0.0-beta.36', 'true', release_sha) }.to raise_error(SystemExit)
      expect(published).to be_empty
    end

    it 'does not publish when CI was red to begin with' do
      ci_results.replace([false])
      expect { run('release:github', '1.0.0-beta.36', 'true', release_sha) }.to raise_error(SystemExit)
      expect(published).to be_empty
    end

    it 'passes the draft task its release commit through to the gate' do
      without_aborting { run('release:draft', '1.0.0-beta.36', 'true', release_sha) }
      expect(published.join).to include('--draft', "--target #{release_sha}")
    ensure
      ENV.delete('DRAFT')
    end

    it 'publishes the resolved commit when given a branch name' do
      without_aborting { run('release:github', '1.0.0-beta.36', 'true', 'HEAD') }
      expect(published.join).to include("--target #{release_sha}")
      expect(published.join).not_to include('--target HEAD')
    end
  end
end
