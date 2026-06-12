# frozen_string_literal: true

require_relative '../../spec_helper'
require 'tmpdir'
require 'json'
require_relative '../../../lib/monadic/utils/degradation_notifier'

RSpec.describe Monadic::Utils::DegradationNotifier do
  let(:log_dir) { Dir.mktmpdir }
  let(:log_file) { File.join(log_dir, described_class::LOG_FILE_NAME) }

  before do
    described_class.reset!
    allow(Monadic::Utils::Environment).to receive(:log_path).and_return(log_dir)
  end

  after do
    described_class.reset!
    FileUtils.remove_entry(log_dir)
  end

  def capture_stderr
    original = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original
  end

  describe '.report' do
    it 'always writes to STDERR regardless of EXTRA_LOGGING' do
      output = capture_stderr do
        described_class.report(component: 'container:python',
                               message: 'failed to start')
      end
      expect(output).to include('[DEGRADED]')
      expect(output).to include('container:python')
      expect(output).to include('failed to start')
    end

    it 'always appends to log/degradation.log' do
      capture_stderr do
        described_class.report(component: 'privacy', message: 'masking unavailable',
                               severity: :error)
        described_class.report(component: 'privacy', message: 'masking unavailable',
                               severity: :error)
      end
      lines = File.readlines(log_file)
      expect(lines.size).to eq(2), 'every event must be logged (dedup applies only to UI)'
      expect(lines.first).to include('[ERROR]')
      expect(lines.first).to include('privacy: masking unavailable')
    end

    it 'normalizes unknown severities to :warning' do
      capture_stderr do
        described_class.report(component: 'x', message: 'y', severity: :bogus)
      end
      expect(File.read(log_file)).to include('[WARNING]')
    end

    context 'UI notification' do
      let(:fake_ws) { class_double('WebSocketHelper') }

      before do
        stub_const('WebSocketHelper', fake_ws)
        allow(fake_ws).to receive(:broadcast_to_all)
      end

      it 'broadcasts a system_info message once per component within the TTL' do
        capture_stderr do
          described_class.report(component: 'embeddings', message: 'unreachable')
          described_class.report(component: 'embeddings', message: 'unreachable')
        end
        expect(fake_ws).to have_received(:broadcast_to_all).once do |json|
          payload = JSON.parse(json)
          expect(payload['type']).to eq('system_info')
          expect(payload['content']).to include('embeddings')
          expect(payload['content']).to include('unreachable')
        end
      end

      it 'notifies separately for distinct components' do
        capture_stderr do
          described_class.report(component: 'embeddings', message: 'unreachable')
          described_class.report(component: 'container:selenium', message: 'not built')
        end
        expect(fake_ws).to have_received(:broadcast_to_all).twice
      end

      it 'notifies again after the dedup TTL has elapsed' do
        capture_stderr do
          described_class.report(component: 'embeddings', message: 'unreachable')
        end
        future = Time.now + described_class::DEDUP_TTL_SECONDS + 1
        allow(Time).to receive(:now).and_return(future)
        capture_stderr do
          described_class.report(component: 'embeddings', message: 'unreachable')
        end
        expect(fake_ws).to have_received(:broadcast_to_all).twice
      end

      it 'never raises when the broadcast fails' do
        allow(fake_ws).to receive(:broadcast_to_all).and_raise(StandardError, 'dead socket')
        expect {
          capture_stderr do
            described_class.report(component: 'embeddings', message: 'unreachable')
          end
        }.not_to raise_error
      end
    end

    it 'never raises when the log directory is unwritable' do
      allow(Monadic::Utils::Environment).to receive(:log_path)
        .and_return('/nonexistent/path/zzz')
      expect {
        capture_stderr do
          described_class.report(component: 'x', message: 'y')
        end
      }.not_to raise_error
    end
  end
end
