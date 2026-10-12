# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/monadic/utils/segment_transcriber'

RSpec.describe Monadic::Utils::SegmentTranscriber do
  # A scripted Realtime transcription server. `respond` receives each event
  # the client writes and returns the server events to queue; `read` hands
  # them back one at a time and returns nil (time ran out) when none is left.
  let(:fake_server) do
    Class.new do
      attr_reader :written, :closed

      def initialize(&respond)
        @respond = respond
        @queue = []
        @written = []
        @closed = false
        @items = 0
      end

      def write(event)
        event = JSON.parse(JSON.generate(event))
        @written << event
        @queue.concat(Array(@respond.call(event, self)))
      end

      def read(_timeout)
        @queue.shift
      end

      def close
        @closed = true
      end

      def next_item
        @items += 1
        "item_#{object_id}_#{@items}"
      end

      def appended_bytes_since_last_commit
        tail = @written.reverse.take_while { |e| e['type'] != 'input_audio_buffer.commit' || e.equal?(@written.last) }
        tail.select { |e| e['type'] == 'input_audio_buffer.append' }.sum { |e| Base64.decode64(e['audio']).bytesize }
      end
    end
  end

  def session_updated(turn_detection: nil)
    { 'type' => 'session.updated',
      'session' => { 'audio' => { 'input' => { 'turn_detection' => turn_detection } } } }
  end

  def committed(conn, item = conn.next_item)
    { 'type' => 'input_audio_buffer.committed', 'event_id' => "server_#{item}", 'item_id' => item,
      'previous_item_id' => nil }
  end

  def completed(item, text, seconds = 1.5)
    { 'type' => described_class::COMPLETED, 'item_id' => item, 'transcript' => text,
      'usage' => { 'type' => 'duration', 'seconds' => seconds } }
  end

  # Replies like the real service: committed then completed, text = which segment it was.
  def well_behaved
    lambda do |event, conn|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit'
        c = committed(conn)
        [c, completed(c['item_id'], "text for #{conn.appended_bytes_since_last_commit} bytes")]
      end
    end
  end

  let(:dir) { Dir.mktmpdir('segment-transcriber') }
  let(:pcm) { File.join(dir, 'audio_24k.pcm') }
  let(:rate) { 24_000 }

  before { File.binwrite(pcm, ([1] * (rate * 40)).pack('s<*')) }
  after { FileUtils.rm_rf(dir) }

  def seg(id, from, to)
    { 'segment_id' => id, 'start_sample' => (from * rate).to_i, 'end_sample' => (to * rate).to_i,
      'speech_regions' => [], 'start_reason' => 'speech_onset', 'end_reason' => 'silence' }
  end

  def segments_doc(*segs)
    { 'schema' => 'speech-segments', 'schema_version' => 1, 'timebase' => 'video_relative_samples',
      'sample_rate_hz' => rate, 'interval_convention' => 'start_inclusive_end_exclusive',
      'timeline_origin_ms' => 0.0, 'status' => segs.empty? ? 'no_speech_detected' : 'complete',
      'segments' => segs }
  end

  # One connection at a time unless a test asks for more (the scripted
  # connections are then handed out in the order they are asked for).
  def transcriber(doc, connections, **opts)
    described_class.new(segments: doc, pcm_path: pcm, model: 'gpt-transcribe',
                        connect: -> { connections.shift || raise(IOError, 'no more connections') },
                        **{ concurrency: 1 }.merge(opts))
  end

  let(:three) { segments_doc(seg('seg000001', 1, 3), seg('seg000002', 5, 6.5), seg('seg000003', 10, 39)) }

  it 'names the language in the session when one is chosen, and none for auto' do
    conn = fake_server.new(&well_behaved)
    transcriber(three, [conn], language: 'ja').run
    expect(conn.written.first.dig('session', 'audio', 'input', 'transcription')).to eq('model' => 'gpt-transcribe', 'language' => 'ja')
    conn = fake_server.new(&well_behaved)
    transcriber(three, [conn], language: 'auto').run
    expect(conn.written.first.dig('session', 'audio', 'input', 'transcription')).to eq('model' => 'gpt-transcribe')
  end

  it 'tells the seconds of audio of each attempt as it is sent' do
    sent = []
    conn = fake_server.new(&well_behaved)
    transcriber(three, [conn], on_attempt: ->(seconds) { sent << seconds }).run
    expect(sent).to eq([2.0, 1.5, 29.0])
  end

  it 'gives the document as far as it has got, with the rest pending' do
    t = transcriber(three, [])
    expect(t.snapshot).to be_nil
    results = three['segments'].to_h { |sg| [sg['segment_id'], { 'status' => 'pending' }] }
                               .merge('seg000001' => { 'status' => 'complete', 'text' => 'Hi.' })
    t.instance_variable_set(:@progress, [three['segments'], results])
    doc = t.snapshot
    expect(doc['status']).to eq('stopped')
    expect(doc['segments'].map { |sg| sg['status'] }).to eq(%w[complete pending pending])
  end

  it 'sends each segment once, commits it, and keeps the segment times' do
    conn = fake_server.new(&well_behaved)
    result = transcriber(three, [conn]).run

    expect(result['status']).to eq('complete')
    expect(result['schema']).to eq('timed-transcript')
    expect(result['segments'].map { |s| s['text'] }).to eq(
      ["text for #{2 * rate * 2} bytes", "text for #{(1.5 * rate * 2).to_i} bytes", "text for #{29 * rate * 2} bytes"]
    )
    expect(result['segments'].map { |s| s['start_sample'] }).to eq([rate, 5 * rate, 10 * rate])
    expect(result['segments'].map { |s| s['usage_seconds'] }).to all(eq(1.5))
    expect(conn.written.count { |e| e['type'] == 'input_audio_buffer.commit' }).to eq(3)
    expect(conn.written.first.dig('session', 'audio', 'input')).to include('turn_detection' => nil)
    expect(conn.written.map { |e| e['type'] }).not_to include('input_audio_buffer.clear')
    expect(conn.closed).to be(true)
  end

  it 'ties the committed item to the segment and records where the text came from' do
    conn = fake_server.new(&well_behaved)
    seg1 = transcriber(three, [conn]).run['segments'].first
    commit = conn.written.find { |e| e['type'] == 'input_audio_buffer.commit' }
    expect(seg1['provenance']).to include('commit_event_id' => commit['event_id'], 'connection_id' => 'conn0001')
    expect(seg1['provenance']['committed_event_id']).to eq("server_#{seg1['provenance']['item_id']}")
    expect(seg1['accepted_attempt_id']).to eq('attempt0001')
  end

  it 'sends the next segment only after the previous one has its text' do
    order = []
    conn = fake_server.new do |event, c|
      order << event['type']
      next [session_updated] if event['type'] == 'session.update'
      next unless event['type'] == 'input_audio_buffer.commit'

      item = committed(c)
      order << :completed
      [item, completed(item['item_id'], 'x')]
    end
    transcriber(three, [conn]).run
    commits = order.each_index.select { |i| order[i] == 'input_audio_buffer.commit' }
    commits.each { |i| expect(order[i + 1]).to eq(:completed) }
  end

  it 'accepts the text when it arrives before the committed event' do
    conn = fake_server.new do |event, c|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit'
        item = committed(c)
        [completed(item['item_id'], 'early'), item]
      end
    end
    expect(transcriber(three, [conn]).run['segments'].map { |s| s['text'] }).to all(eq('early'))
  end

  it 'does not take the text of another item, and ignores a repeated committed event' do
    conn = fake_server.new do |event, c|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit'
        item = committed(c)
        [item, completed('item_someone_else', 'wrong'), item, completed(item['item_id'], 'right')]
      end
    end
    expect(transcriber(three, [conn]).run['segments'].map { |s| s['text'] }).to all(eq('right'))
  end

  it 'replaces a connection that commits an unexpected second item and sends the segment again' do
    confused = fake_server.new do |event, c|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit'
        a = committed(c)
        b = committed(c)
        [a, b, completed(a['item_id'], 'first item'), completed(b['item_id'], 'second item')]
      end
    end
    healthy = fake_server.new(&well_behaved)
    result = transcriber(three, [confused, healthy]).run

    expect(result['status']).to eq('complete')
    expect(confused.closed).to be(true)
    first = result['segments'].first
    expect(first['attempts']).to eq(2)
    expect(first['accepted_attempt_id']).to eq('attempt0002')
    expect(first['provenance']['connection_id']).to eq('conn0002')
    expect(result['segments'].map { |s| s['text'] }).to all(start_with('text for'))
  end

  it 'refuses a session where the server detects turns itself' do
    vad = fake_server.new { |e, _| [session_updated(turn_detection: { 'type' => 'server_vad' })] if e['type'] == 'session.update' }
    result = transcriber(three, [vad], max_connections: 1).run
    expect(result['status']).to eq('failed')
    expect(vad.written.map { |e| e['type'] }).to eq(['session.update'])
  end

  it 'stops when speech events show the server is segmenting the audio' do
    conn = fake_server.new do |event, _|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit' then [{ 'type' => 'input_audio_buffer.speech_started', 'audio_start_ms' => 0 }]
      end
    end
    result = transcriber(three, Array.new(9) { conn }, max_attempts: 1).run
    expect(result['segments'].map { |s| s['error'] }).to all(eq('protocol: server turn detection is on'))
  end

  it 'treats an empty-commit error for a non-empty segment as a failure, not as the end of the audio' do
    conn = fake_server.new do |event, _|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit'
        [{ 'type' => 'error', 'error' => { 'code' => 'input_audio_buffer_commit_empty', 'event_id' => event['event_id'] } }]
      end
    end
    result = transcriber(three, Array.new(9) { conn }, max_attempts: 1).run
    expect(result['status']).to eq('failed')
    expect(result['segments'].first['error']).to eq('protocol: commit of a segment arrived empty')
    expect(result['coverage']['unresolved_segment_ids']).to eq(%w[seg000001 seg000002 seg000003])
  end

  it 'retries a segment whose transcription failed and keeps going with the rest' do
    failures = 0
    conn = fake_server.new do |event, c|
      case event['type']
      when 'session.update' then [session_updated]
      when 'input_audio_buffer.commit'
        item = committed(c)
        if event['event_id'].start_with?('seg000002') && (failures += 1) <= 5
          [item, { 'type' => described_class::FAILED, 'item_id' => item['item_id'], 'error' => { 'code' => 'x' } }]
        else
          [item, completed(item['item_id'], 'ok')]
        end
      end
    end
    result = transcriber(three, [conn], max_attempts: 3).run
    expect(result['status']).to eq('partial')
    second = result['segments'][1]
    expect(second).to include('status' => 'failed', 'attempts' => 3, 'error' => 'transcription failed (x)')
    expect(result['segments'].values_at(0, 2).map { |s| s['text'] }).to eq(%w[ok ok])
  end

  it 'gives up on a segment after repeated silence from the server, on fresh connections' do
    silent = -> { fake_server.new { |e, _| [session_updated] if e['type'] == 'session.update' } }
    conns = Array.new(3) { silent.call } + [fake_server.new(&well_behaved)]
    result = transcriber(three, conns, max_attempts: 3).run
    expect(result['segments'].first).to include('status' => 'failed', 'error' => 'timeout', 'attempts' => 3)
    expect(result['segments'].drop(1).map { |s| s['status'] }).to all(eq('complete'))
    expect(result['status']).to eq('partial')
  end

  it 'stops sending when the chat is cancelled' do
    sent = 0
    cancel = false
    conn = fake_server.new do |event, c|
      next [session_updated] if event['type'] == 'session.update'
      next unless event['type'] == 'input_audio_buffer.commit'

      sent += 1
      cancel = true
      item = committed(c)
      [item, completed(item['item_id'], 'one')]
    end
    result = transcriber(three, [conn], cancelled: -> { cancel }).run
    expect(sent).to eq(1)
    expect(result['status']).to eq('cancelled')
    expect(result['segments'].map { |s| s['status'] }).to eq(%w[complete pending pending])
  end

  it 'does not connect when there is no speech' do
    result = transcriber(segments_doc, []).run
    expect(result['status']).to eq('no_speech_detected')
    expect(result['segments']).to eq([])
  end

  it 'refuses a segment that reaches past the end of the audio' do
    doc = segments_doc(seg('seg000001', 39, 41))
    result = transcriber(doc, Array.new(9) { fake_server.new(&well_behaved) }, max_attempts: 2).run
    expect(result['segments'].first).to include('status' => 'failed', 'error' => 'protocol: audio shorter than the segment')
  end

  it 'stops after the connection limit and reports what is left' do
    result = transcriber(three, [], max_connections: 2).run
    expect(result['status']).to eq('failed')
    expect(result['segments'].map { |s| s['error'] }).to all(eq('connection_limit'))
  end

  describe 'several connections at once' do
    # A connection whose replies take a moment, so the others go on meanwhile
    # (the workers are fibers: sleeping in one lets the next one run).
    def slow(conn, delay: 0.02)
      conn.define_singleton_method(:read) do |timeout|
        sleep delay
        super(timeout)
      end
      conn
    end

    let(:six) { segments_doc(*Array.new(6) { |i| seg(format('seg%06d', i + 1), i * 5, i * 5 + 1 + i * 0.5) }) }

    it 'sends segments on several connections at the same time, each tied to its own text' do
      in_flight = 0
      most = 0
      conns = Array.new(3) do
        slow(fake_server.new do |event, c|
          case event['type']
          when 'session.update' then [session_updated]
          when 'input_audio_buffer.commit'
            in_flight += 1
            most = [most, in_flight].max
            item = committed(c)
            [item, completed(item['item_id'], "text for #{c.appended_bytes_since_last_commit} bytes")]
          end
        end)
      end
      done = lambda do |_seg, _result|
        in_flight -= 1
      end
      result = transcriber(six, conns.dup, concurrency: 3, on_progress: done).run
      expect(result['status']).to eq('complete')
      expect(most).to be >= 2
      expect(result['segments'].map { |sg| sg['provenance']['connection_id'] }.uniq.size).to eq(3)
      six['segments'].each_with_index do |sg, i|
        bytes = (sg['end_sample'] - sg['start_sample']) * 2
        expect(result['segments'][i]['text']).to eq("text for #{bytes} bytes")
      end
    end

    it 'gives the segment of a lost connection back to be sent on another' do
      dropping = slow(fake_server.new do |event, _c|
        next [session_updated] if event['type'] == 'session.update'
      end)
      dropping.define_singleton_method(:read) do |timeout|
        sleep 0.01
        raise IOError, 'connection closed' if @written.any? { |e| e['type'] == 'input_audio_buffer.commit' }

        super(timeout)
      end
      conns = [dropping] + Array.new(4) { slow(fake_server.new(&well_behaved)) }
      result = transcriber(six, conns, concurrency: 2).run
      expect(result['status']).to eq('complete')
      expect(result['segments'].map { |sg| sg['status'] }).to all(eq('complete'))
      expect(result['segments'].map { |sg| sg['attempts'] }.sum).to eq(7) # one segment sent twice
    end

    it 'stops every connection when the chat is cancelled' do
      cancel = false
      commits = 0
      conns = Array.new(3) do
        slow(fake_server.new do |event, c|
          next [session_updated] if event['type'] == 'session.update'
          next unless event['type'] == 'input_audio_buffer.commit'

          commits += 1
          cancel = true
          item = committed(c)
          [item, completed(item['item_id'], 'x')]
        end)
      end
      result = transcriber(six, conns.dup, concurrency: 3, cancelled: -> { cancel }).run
      expect(result['status']).to eq('cancelled')
      expect(commits).to be <= 3
      expect(result['segments'].count { |sg| sg['status'] == 'pending' }).to be >= 3
      expect(conns.map(&:closed)).to all(be(true))
    end
  end

  describe 'runs of segments, rate limits and refusals' do
    let(:six) { segments_doc(*Array.new(6) { |i| seg(format('seg%06d', i + 1), i * 5, i * 5 + 2) }) }

    it 'gives each connection a run of consecutive segments of about the same length' do
      conns = Array.new(3) { fake_server.new(&well_behaved) }
      result = transcriber(six, conns.dup, concurrency: 3).run
      by_conn = result['segments'].group_by { |sg| sg['provenance']['connection_id'] }
      expect(by_conn.values.map { |sgs| sgs.map { |sg| sg['segment_id'] } })
        .to match_array([%w[seg000001 seg000002], %w[seg000003 seg000004], %w[seg000005 seg000006]])
    end

    it 'waits before connecting again after a rate limit, then goes on' do
      stub_const("#{described_class}::RATE_LIMIT_WAIT", 0.2)
      opened = []
      limited = fake_server.new { |e, _| [{ 'type' => 'error', 'error' => { 'code' => 'rate_limit_exceeded' } }] if e['type'] == 'session.update' }
      conns = [limited, fake_server.new(&well_behaved)]
      connect = lambda do
        opened << Process.clock_gettime(Process::CLOCK_MONOTONIC)
        conns.shift
      end
      t = described_class.new(segments: three, pcm_path: pcm, model: 'gpt-transcribe', connect: connect, concurrency: 1)
      result = t.run
      expect(result['status']).to eq('complete')
      expect(opened[1] - opened[0]).to be >= 0.14 # 0.2 s with up to 25 % less for jitter
    end

    it 'stops every connection when the service refuses for good, and says why' do
      connect = -> { raise described_class::Refused, 'the connection was refused (401)' }
      t = described_class.new(segments: six, pcm_path: pcm, model: 'gpt-transcribe', connect: connect, concurrency: 3)
      result = t.run
      expect(result['status']).to eq('failed')
      expect(result['segments'].map { |sg| sg['error'] }).to all(eq('refused'))
    end

    it 'stops every connection when the session refuses the key' do
      opened = 0
      connect = lambda do
        opened += 1
        fake_server.new { |e, _| [{ 'type' => 'error', 'error' => { 'code' => 'invalid_api_key' } }] if e['type'] == 'session.update' }
      end
      t = described_class.new(segments: six, pcm_path: pcm, model: 'gpt-transcribe', connect: connect, concurrency: 1)
      result = t.run
      expect(opened).to eq(1)
      expect(result['segments'].map { |sg| sg['error'] }).to all(eq('refused'))
    end

    it 'tries the next address of the host when one is unreachable' do
      endpoint = double(each: nil)
      allow(endpoint).to receive(:each).and_yield(:v6).and_yield(:v4)
      tried = []
      conn = described_class::WebSocketConnection.connect_any(endpoint) do |address|
        tried << address
        raise Errno::EHOSTUNREACH if address == :v6

        :connected
      end
      expect(conn).to eq(:connected)
      expect(tried).to eq(%i[v6 v4])
    end

    it 'raises the last error when no address of the host can be reached' do
      endpoint = double
      allow(endpoint).to receive(:each).and_yield(:v6).and_yield(:v4)
      expect do
        described_class::WebSocketConnection.connect_any(endpoint) { |_| raise Errno::EHOSTUNREACH }
      end.to raise_error(Errno::EHOSTUNREACH)
    end

    it 'does not send a segment again on the same connection once the chat is cancelled' do
      commits = 0
      cancel = false
      conn = fake_server.new do |event, c|
        next [session_updated] if event['type'] == 'session.update'
        next unless event['type'] == 'input_audio_buffer.commit'

        commits += 1
        cancel = true
        item = committed(c)
        [item, { 'type' => described_class::FAILED, 'item_id' => item['item_id'], 'error' => { 'code' => 'x' } }]
      end
      result = transcriber(three, [conn], cancelled: -> { cancel }).run
      expect(commits).to eq(1)
      expect(result['status']).to eq('cancelled')
    end

    it 'keeps why a segment that never got a connection could not be sent' do
      silent = -> { fake_server.new { |_e, _c| nil } } # the session never starts
      result = transcriber(three, Array.new(2) { silent.call }, max_connections: 2).run
      expect(result['segments'].first).to include('error' => 'connection_limit', 'last_error' => 'timeout')
    end
  end

  describe Monadic::Utils::SegmentTranscriber::Batch do
    def batch(doc, transcribe, **opts)
      described_class.new(segments: doc, pcm_path: pcm, model: 'xai-stt', transcribe: transcribe, **opts)
    end

    it 'sends each segment as a WAV of exactly its samples and keeps the segment times' do
      sent = []
      result = batch(three, lambda { |wav|
        sent << wav
        "#{wav.bytesize - 44} bytes"
      }).run
      expect(result['status']).to eq('complete')
      expect(result['model']).to eq('xai-stt')
      expect(result['segments'].map { |s| s['text'] }).to eq(["#{2 * rate * 2} bytes", "#{(1.5 * rate * 2).to_i} bytes",
                                                                 "#{29 * rate * 2} bytes"])
      expect(result['segments'].map { |s| s['start_sample'] }).to eq([rate, 5 * rate, 10 * rate])
      header = sent.min_by(&:bytesize)[0, 44].unpack('a4Va4a4VvvVVvva4V')
      expect(header.values_at(0, 2, 5, 6, 7, 10)).to eq(['RIFF', 'WAVE', 1, 1, rate, 16])
    end

    it 'sends no more than the given number at a time' do
      running = 0
      peak = 0
      batch(segments_doc(*Array.new(8) { |i| seg("seg#{i}", i * 2, (i * 2) + 1) }), lambda { |_wav|
        running += 1
        peak = [peak, running].max
        sleep 0.01
        running -= 1
        'ok'
      }, concurrency: 3).run
      expect(peak).to eq(3)
    end

    it 'tries a failing segment again, then records it as failed and keeps the others' do
      calls = Hash.new(0)
      result = batch(three, lambda { |wav|
        calls[wav.bytesize] += 1
        next 'ERROR: xAI STT Error (500): busy' if wav.bytesize == 44 + (1.5 * rate * 2).to_i

        calls[wav.bytesize] == 1 ? 'ERROR: timeout' : 'second try'
      }, max_attempts: 3).run
      expect(result['status']).to eq('partial')
      expect(result['segments'].map { |s| s['status'] }).to eq(%w[complete failed complete])
      expect(result['segments'][0]).to include('text' => 'second try', 'attempts' => 2, 'accepted_attempt_id' => 'attempt0002')
      expect(result['segments'][1]).to include('attempts' => 3, 'error' => 'xAI STT Error (500): busy')
    end

    it 'treats an exception like a failed attempt' do
      result = batch(three, ->(_wav) { raise IOError, 'socket closed' }, max_attempts: 2).run
      expect(result['status']).to eq('failed')
      expect(result['segments'].map { |s| s['error'] }).to all(eq('IOError'))
    end

    it 'stops sending when the chat changes' do
      count = 0
      cancel = false
      result = batch(three, lambda { |_wav|
        count += 1
        cancel = true
        'one'
      }, concurrency: 1, cancelled: -> { cancel }).run
      expect(count).to eq(1)
      expect(result['status']).to eq('cancelled')
      expect(result['segments'].map { |s| s['status'] }).to eq(%w[complete pending pending])
    end

    it 'refuses a segment that reaches past the end of the audio without sending it' do
      sent = 0
      result = batch(segments_doc(seg('seg000001', 39, 41)), ->(_wav) { (sent += 1) && 'x' }).run
      expect(sent).to eq(0)
      expect(result['segments'].first).to include('status' => 'failed', 'error' => 'protocol: audio shorter than the segment')
    end
  end
end
