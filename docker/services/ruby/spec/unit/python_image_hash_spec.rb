# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'

# The hash monadic.sh keeps of the Python image's sources, run as it is on a
# folder made for the test.
RSpec.describe 'the hash of what goes into the Python image' do
  let(:script) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }
  let(:function) { script[/^calculate_python_image_hash\(\) \{.*?^\}$/m] or raise 'function not found' }

  def hash_of(root)
    out, status = Open3.capture2('bash', '-c', "ROOT_DIR=\"$1\"\n#{function}\ncalculate_python_image_hash", 'bash', root)
    raise 'hash failed' unless status.success?
    out.strip
  end

  def with_sources
    Dir.mktmpdir do |root|
      dir = File.join(root, 'services', 'python')
      FileUtils.mkdir_p(File.join(dir, 'scripts', 'cli tools'))
      File.write(File.join(dir, 'Dockerfile'), "FROM scratch\n")
      File.write(File.join(dir, 'compose.yml'), "services: {}\n")
      File.write(File.join(dir, 'scripts', 'cli tools', 'navigator.py'), "print(1)\n")
      yield root, dir
    end
  end

  it 'changes when a script changes, with the Dockerfile as it was' do
    with_sources do |root, dir|
      before = hash_of(root)
      expect(before).to match(/\A\h{64}\z/)
      File.write(File.join(dir, 'scripts', 'cli tools', 'navigator.py'), "print(2)\n")
      expect(hash_of(root)).not_to eq(before)
    end
  end

  it 'changes when a file is added or the Dockerfile changes' do
    with_sources do |root, dir|
      before = hash_of(root)
      File.write(File.join(dir, 'scripts', 'new.py'), "print(3)\n")
      added = hash_of(root)
      expect(added).not_to eq(before)
      File.write(File.join(dir, 'Dockerfile'), "FROM scratch\nRUN true\n")
      expect(hash_of(root)).not_to eq(added)
    end
  end

  it 'stays the same for what is not in the image' do
    with_sources do |root, dir|
      before = hash_of(root)
      File.write(File.join(dir, 'compose.yml'), "services: {a: {}}\n")
      FileUtils.mkdir_p(File.join(dir, 'scripts', '__pycache__'))
      File.write(File.join(dir, 'scripts', '__pycache__', 'x.cpython-312.pyc'), 'bytecode')
      File.write(File.join(dir, 'scripts', 'y.pyc'), 'bytecode')
      File.write(File.join(dir, '.DS_Store'), 'finder')
      expect(hash_of(root)).to eq(before)
    end
  end

  it 'says so when the sources are not there' do
    Dir.mktmpdir { |root| expect(hash_of(root)).to eq('file_not_found') }
  end

  it 'is what both the saved record and the check at an update use' do
    expect(script.scan('local python_hash=$(calculate_python_image_hash)').size).to eq(2)
    expect(script).not_to match(/python_hash=\$\(calculate_docker_hash/)
  end
end
