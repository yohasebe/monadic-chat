# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'

# image_refs in monadic.sh, run as it is against the image lists a Docker
# engine and a Podman engine give.
RSpec.describe 'image_refs in monadic.sh' do
  let(:function) do
    script = File.read(File.expand_path('../../../../monadic.sh', __dir__))
    script[/^image_refs\(\) \{.*?^\}$/m] or raise 'image_refs not found'
  end

  def refs(listing, *names)
    Dir.mktmpdir do |dir|
      fake = File.join(dir, 'docker')
      File.write(fake, "#!/bin/bash\ncat <<'LIST'\n#{listing}\nLIST\n")
      File.chmod(0o755, fake)
      out, status = Open3.capture2('bash', '-c', "DOCKER=#{fake}\n#{function}\nimage_refs \"$@\"", 'bash', *names)
      raise 'image_refs failed' unless status.success?
      out.split("\n")
    end
  end

  docker_list = <<~LIST.chomp
    yohasebe/monadic-privacy:latest
    ghcr.io/yohasebe/monadic-privacy:latest
    yohasebe/python-tools:dev
    yohasebe/python:1.0.0
    yohasebe/monadic-chat:<none>
  LIST
  podman_list = <<~LIST.chomp
    docker.io/yohasebe/monadic-privacy:latest
    ghcr.io/yohasebe/monadic-privacy:latest
    docker.io/yohasebe/python-tools:dev
    docker.io/yohasebe/python:1.0.0
  LIST

  it 'takes a docker.io name in both forms and leaves other registries' do
    expect(refs(docker_list, 'yohasebe/monadic-privacy')).to eq(['yohasebe/monadic-privacy:latest'])
    expect(refs(podman_list, 'yohasebe/monadic-privacy')).to eq(['docker.io/yohasebe/monadic-privacy:latest'])
  end

  it 'takes a name with its registry only from that registry' do
    expect(refs(podman_list, 'ghcr.io/yohasebe/monadic-privacy')).to eq(['ghcr.io/yohasebe/monadic-privacy:latest'])
  end

  it 'shortens docker.io/library/ only for a one-part name' do
    list = "docker.io/library/qdrant/qdrant:latest\ndocker.io/library/alpine:3.20"
    expect(refs(list, 'qdrant/qdrant')).to eq([])
    expect(refs(list, 'alpine')).to eq(['docker.io/library/alpine:3.20'])
  end

  it 'takes an image Podman built itself when its localhost/ name is given' do
    list = "localhost/yohasebe/monadic-chat:old\ndocker.io/yohasebe/monadic-chat:2.0.0"
    expect(refs(list, 'yohasebe/monadic-chat', 'localhost/yohasebe/monadic-chat'))
      .to eq(['localhost/yohasebe/monadic-chat:old', 'docker.io/yohasebe/monadic-chat:2.0.0'])
  end

  it 'matches whole names only, and skips untagged images' do
    expect(refs(docker_list, 'yohasebe/python')).to eq(['yohasebe/python:1.0.0'])
    expect(refs(docker_list, 'yohasebe/monadic-chat')).to eq([])
  end
end

# The cleanups built on image_refs, run as they are against a stand-in docker
# that records what it is asked to remove.
RSpec.describe 'image cleanups in monadic.sh' do
  let(:script) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }

  def functions(*names)
    names.map { |name| script[/^#{name}\(\) \{.*?^\}$/m] or raise "#{name} not found" }.join("\n")
  end

  # images: lines of repository:tag; ids: ref => image ID
  def removed(call, images:, ids: {})
    Dir.mktmpdir do |dir|
      log = File.join(dir, 'rmi.log')
      fake = File.join(dir, 'docker')
      inspect_cases = ids.map { |ref, id| "    #{ref}) echo #{id} ;;" }.join("\n")
      File.write(fake, <<~SH)
        #!/bin/bash
        case "$1" in
          images) cat <<'LIST'
        #{images.join("\n")}
        LIST
          ;;
          image)
            case "${@: -1}" in
        #{inspect_cases}
              *) exit 1 ;;
            esac ;;
          rmi) echo "${@: -1}" >> "#{log}" ;;
        esac
      SH
      File.chmod(0o755, fake)
      body = "DOCKER=#{fake}\nMONADIC_VERSION=2.0.0\n#{functions('image_refs', 'remove_older_images', 'remove_legacy_prebuilt_images')}\n#{call}"
      _out, status = Open3.capture2('bash', '-c', body)
      raise 'cleanup failed' unless status.success?
      File.exist?(log) ? File.read(log).split("\n") : []
    end
  end

  it 'keeps every older Ruby image when this version has none' do
    expect(removed('remove_older_images yohasebe/monadic-chat',
                   images: ['yohasebe/monadic-chat:1.0.0', 'yohasebe/monadic-chat:latest'],
                   ids: { 'yohasebe/monadic-chat:1.0.0' => 'a', 'yohasebe/monadic-chat:latest' => 'a' })).to eq([])
  end

  it 'removes older Ruby images by name and keeps the tags of this version' do
    expect(removed('remove_older_images yohasebe/monadic-chat',
                   images: ['yohasebe/monadic-chat:2.0.0', 'yohasebe/monadic-chat:latest', 'yohasebe/monadic-chat:1.0.0'],
                   ids: { 'yohasebe/monadic-chat:2.0.0' => 'b', 'yohasebe/monadic-chat:latest' => 'b',
                          'yohasebe/monadic-chat:1.0.0' => 'a' })).to eq(['yohasebe/monadic-chat:1.0.0'])
  end

  it 'removes only the latest tag of a legacy image, and never the ghcr.io ones' do
    expect(removed('remove_legacy_prebuilt_images',
                   images: ['qdrant/qdrant:latest', 'qdrant/qdrant:v1.19.1', 'ghcr.io/yohasebe/monadic-privacy:latest'])).to eq(['qdrant/qdrant:latest'])
  end
end
