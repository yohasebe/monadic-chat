# frozen_string_literal: true

require 'spec_helper'
require 'monadic/shell'

RSpec.describe Monadic::Shell do
  describe '.resolve_container' do
    it 'maps known symbols to the docker container name' do
      expect(described_class.resolve_container(:python)).to eq('monadic-chat-python-container')
      expect(described_class.resolve_container(:ruby)).to eq('monadic-chat-ruby-container')
      expect(described_class.resolve_container(:extractor)).to eq('monadic-chat-extractor-container')
    end

    it 'raises a structured error for unknown containers' do
      expect { described_class.resolve_container(:unknown) }
        .to raise_error(described_class::UnknownContainerError, /unknown/i)
    end
  end

  describe '.escape' do
    it 'quotes shell metacharacters' do
      expect(described_class.escape('foo bar')).to eq('foo\\ bar')
      expect(described_class.escape('a;b')).to eq('a\\;b')
      expect(described_class.escape("it's")).to match(/it.+s/)
    end

    it 'is idempotent for plain identifiers' do
      expect(described_class.escape('plain123')).to eq('plain123')
    end
  end

  describe '.exec' do
    it 'rejects an empty argv' do
      expect { described_class.exec(container: :python, argv: []) }
        .to raise_error(ArgumentError, /argv/)
    end

    it 'builds a docker exec invocation with the container resolved and argv passed through' do
      captured = nil
      allow(Open3).to receive(:capture3) do |*args|
        captured = args
        ['stdout', '', double('Status', success?: true)]
      end

      described_class.exec(container: :python, argv: ['pdf2txt.py', 'file.pdf'], workdir: '/work')

      expect(captured).to eq([
        'docker', 'exec', '-w', '/work', 'monadic-chat-python-container',
        'pdf2txt.py', 'file.pdf'
      ])
    end

    it 'passes env vars via -e flags in argv order' do
      captured = nil
      allow(Open3).to receive(:capture3) do |*args|
        captured = args
        ['', '', double('Status', success?: true)]
      end

      described_class.exec(container: :python, argv: ['env'], env: { 'FOO' => 'bar', 'BAZ' => 'qux' })

      expect(captured).to include('-e', 'FOO=bar', '-e', 'BAZ=qux')
    end

    # Real processes, not a stubbed Open3: the stub once hid that
    # Open3.capture3 has no timeout option, so every timed call raised.
    it 'returns the output of a command that finishes within the timeout' do
      stdout, stderr, status = described_class.capture(['sh', '-c', 'echo out; echo err >&2'], timeout: 5)
      expect([stdout, stderr, status.success?]).to eq(["out\n", "err\n", true])
    end

    it 'stops a command that runs over the timeout and says so' do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { described_class.capture(['sleep', '10'], timeout: 1) }
        .to raise_error(Monadic::Shell::TimedOut, /did not finish within 1 seconds/)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
    end

    it 'passes the timeout from exec to the command it runs' do
      expect(described_class).to receive(:capture).with(array_including('docker', 'exec', 'true'), timeout: 5)
        .and_return(['', '', double(success?: true)])
      described_class.exec(container: :python, argv: ['true'], timeout: 5)
    end
  end

  describe '.bash' do
    it 'wraps the body in bash -c as a single argv element' do
      captured = nil
      allow(Open3).to receive(:capture3) do |*args|
        captured = args
        ['', '', double('Status', success?: true)]
      end

      body = "echo 'hello world'; echo done"
      described_class.bash(container: :python, body: body)

      # Final three argv elements are bash -c BODY. The whole point of
      # the shape is that BODY is one argv element, so the docker layer
      # cannot split it on whitespace or quotes.
      expect(captured[-3..-1]).to eq(['bash', '-c', body])
    end

    it 'rejects a non-string body' do
      expect { described_class.bash(container: :python, body: nil) }
        .to raise_error(ArgumentError, /String/)
    end
  end

  describe '.cp_to_container' do
    it 'invokes docker cp with the container path joined' do
      captured = nil
      allow(Open3).to receive(:capture3) do |*args|
        captured = args
        ['', '', double('Status', success?: true)]
      end

      described_class.cp_to_container(
        container: :python, host_path: '/tmp/x.txt', container_path: '/monadic/data/x.txt'
      )

      expect(captured).to eq([
        'docker', 'cp', '/tmp/x.txt', 'monadic-chat-python-container:/monadic/data/x.txt'
      ])
    end
  end
end
