require 'spec_helper'

# A trial build of an already published version produces files with the same
# names as that release's assets but different contents. release:github must
# stop before such files could replace the published ones; replacing assets is
# the separate, explicit release:update_assets task.
RSpec.describe 'the existing-release guard in release:github' do
  let(:root) { File.expand_path('../../../../../..', __dir__) }
  let(:task) do
    rake = File.read(File.join(root, 'rakelib/release.rake'))
    start = rake.index('  task :github, [:version')
    rake[start...rake.index("\n  task ", start + 1)]
  end

  it 'asks gh whether a release for the tag exists, and stops if it does' do
    expect(task).to include('Open3.capture2e("gh", "release", "view", "v#{version}"')
    expect(task).to include('already exists; nothing was built or published')
    expect(task).to include('release:update_assets')
  end

  it 'proceeds only on gh\'s own "release not found", so a failed check stops too' do
    expect(task).to include('!existing.include?("release not found")')
    expect(task).to include('could not check whether')
  end

  it 'runs before CI is checked, packages are built or anything is published' do
    guard = task.index('already exists; nothing was built or published')
    expect(guard).to be < task.index('verify_release_ci_green(target)')
    expect(guard).to be < task.index('release_cmd = "gh release create')
  end
end
