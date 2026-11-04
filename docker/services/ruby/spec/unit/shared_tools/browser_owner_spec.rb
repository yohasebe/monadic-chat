# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/web_automation"
require_relative "../../../lib/monadic/history/policy"

# Who may open a browser session: each chat its own browser, short jobs a
# slot of their own, admitted from what Selenium reports.
RSpec.describe MonadicSharedTools::BrowserOwner do
  let(:owner) { described_class }
  # What Selenium reports, as web_navigator.py --action status prints it.
  let(:status) { { sessions: [], max: 3 } }

  before do
    owner.reset!
    allow(owner).to receive(:observe) { status.dup }
    allow(owner).to receive(:start_worker)
  end

  # The user leaves the chat (Reset): Chats ends its epoch and tells
  # BrowserOwner.
  def replace(chat)
    Monadic::Workspace::Chats.replacing!({ chat_id: chat })
  end

  def open_browser(chat, session)
    epoch = owner.epoch(chat)
    expect(owner.begin_start(chat, epoch)).to eq(:ok)
    expect(owner.finish_start(chat, session, epoch)).to be(true)
    status[:sessions] += [session]
    epoch
  end

  # Starts jobs one inside another, as long as they are admitted: how many.
  def admitted_jobs(limit)
    count = 0
    nest = lambda do |left|
      next if left.zero?

      owner.with_job do
        count += 1
        nest.call(left - 1)
      end
    end
    nest.call(limit)
    count
  rescue described_class::Full
    count
  end

  describe 'admission' do
    it 'gives each chat its own browser' do
      a = open_browser('a', 'wd-a')
      b = open_browser('b', 'wd-b')
      expect(owner.session_for('a', a)).to eq('wd-a')
      expect(owner.session_for('b', b)).to eq('wd-b')
      expect(owner.session_for('c', owner.epoch('c'))).to be_nil
    end

    it 'keeps one slot for short jobs: at most total - 1 chats hold a browser' do
      open_browser('a', 'wd-a')
      open_browser('b', 'wd-b')
      expect(owner.begin_start('c', owner.epoch('c'))).to eq(:chats_full)
      expect(admitted_jobs(1)).to eq(1)
    end

    it 'takes the number of slots from Selenium' do
      status[:max] = 2
      open_browser('a', 'wd-a')
      expect(owner.begin_start('b', owner.epoch('b'))).to eq(:chats_full)
    end

    it 'lets one chat keep the only slot when Selenium has one' do
      status[:max] = 1
      open_browser('a', 'wd-a')
      expect(owner.begin_start('b', owner.epoch('b'))).to eq(:chats_full)
      expect(admitted_jobs(1)).to eq(0)
    end

    it 'counts sessions Selenium still holds that nobody here tracks, beside jobs not started yet' do
      status[:sessions] = %w[leak-1 leak-2]
      expect(admitted_jobs(3)).to eq(1)
    end

    it "counts a job's session once when the job names it" do
      open_browser('a', 'wd-a')
      owner.with_job do |name_session|
        name_session.call('job-1')
        status[:sessions] += ['job-1']
        expect(admitted_jobs(1)).to eq(1)
      end
    end

    it 'counts the starts and jobs Selenium does not show yet' do
      expect(owner.begin_start('a', owner.epoch('a'))).to eq(:ok)
      owner.with_job do
        owner.with_job do
          expect(owner.begin_start('b', owner.epoch('b'))).to eq(:full)
        end
      end
    end

    it 'reads Selenium again when a slot was given up while it read' do
      calls = 0
      allow(owner).to receive(:observe) do
        calls += 1
        if calls == 1
          replace('x') # a slot given up meanwhile
          { sessions: [], max: 3 }
        else
          { sessions: %w[left-1 left-2 left-3], max: 3 }
        end
      end
      expect { owner.with_job { nil } }.to raise_error(described_class::Full)
      expect(calls).to eq(2)
    end

    it "reads Selenium again when a job ended while it read, and counts the session the job left" do
      job_done = false
      reading = false
      allow(owner).to receive(:observe) do
        if !job_done && !reading
          reading = true
          owner.with_job { nil } # a job ends while this report is read; its session did not close
          job_done = true
          next({ sessions: %w[other-1 other-2], max: 3 }) # read before the job's session showed
        end
        { sessions: job_done ? %w[other-1 other-2 left] : %w[other-1 other-2], max: 3 }
      end
      expect { owner.with_job { nil } }.to raise_error(described_class::Full)
    end

    it 'refuses after OBSERVE_TRIES reads when the slots keep changing' do
      calls = 0
      allow(owner).to receive(:observe) do
        calls += 1
        replace("churn-#{calls}")
        { sessions: [], max: 3 }
      end
      expect { owner.with_job { nil } }.to raise_error(described_class::Full)
      expect(calls).to eq(described_class::OBSERVE_TRIES)
      expect(owner.snapshot[:jobs]).to eq(0)
    end

    it 'opens nothing when Selenium cannot be asked' do
      allow(owner).to receive(:observe).and_return(nil)
      ran = false
      expect { owner.with_job { ran = true } }.to raise_error(described_class::Unavailable)
      expect(ran).to be(false)
      expect(owner.begin_start('a', owner.epoch('a'))).to eq(:unavailable)
    end

    it 'gives a job slot back when the job raises' do
      expect { owner.with_job { raise 'boom' } }.to raise_error('boom')
      expect(owner.snapshot[:jobs]).to eq(0)
    end

    it 'refuses a job in a Private chat before it runs' do
      allow(Monadic::History::Policy).to receive(:current_work_private?).and_return(true)
      ran = false
      expect { owner.with_job { ran = true } }.to raise_error(described_class::PrivateChat)
      expect(ran).to be(false)
      expect(owner.snapshot[:jobs]).to eq(0)
    end
  end

  describe 'a replaced chat' do
    before { allow(owner).to receive(:close_later) }

    it 'has its browser closed in the background, and its work opens nothing more' do
      old = open_browser('a', 'wd-a')
      replace('a')
      expect(owner).to have_received(:close_later).with('wd-a')
      expect(owner.session_for('a', old)).to be_nil
      expect(owner.begin_start('a', old)).to eq(:replaced)
    end

    it 'does not keep a session a start made after the chat was replaced' do
      old = owner.epoch('a')
      expect(owner.begin_start('a', old)).to eq(:ok)
      replace('a')
      expect(owner.finish_start('a', 'wd-late', old)).to be(false)
      expect(owner.snapshot[:browsers]).to be_empty
      expect(owner.snapshot[:starting]).to be_empty
    end

    it "keeps old work out when the chat id comes back (history Continue)" do
      old = owner.epoch('a')
      expect(owner.begin_start('a', old)).to eq(:ok)
      replace('a')
      fresh = owner.epoch('a')
      expect(owner.finish_start('a', 'wd-old-work', old)).to be(false)
      open_browser('a', 'wd-new')
      expect(owner.release('a', old)).to be_nil
      expect(owner.session_for('a', fresh)).to eq('wd-new')
    end

    it 'follows the Chats event' do
      old = open_browser('a', 'wd-a')
      replace('a')
      expect(owner.replaced?('a', old)).to be(true)
      expect(owner).to have_received(:close_later).with('wd-a')
    end
  end

  describe 'idle browsers' do
    before { allow(owner).to receive(:close).and_return(true) }

    it 'closes a browser unused for IDLE_LIMIT' do
      epoch = open_browser('a', 'wd-a')
      owner.reap(now: owner.clock + described_class::IDLE_LIMIT + 1)
      expect(owner).to have_received(:close).with('wd-a')
      expect(owner.session_for('a', epoch)).to be_nil
    end

    it 'leaves a browser an action is using' do
      epoch = open_browser('a', 'wd-a')
      owner.op_lock('a').synchronize do
        owner.reap(now: owner.clock + described_class::IDLE_LIMIT + 1)
      end
      expect(owner).not_to have_received(:close)
      expect(owner.session_for('a', epoch)).to eq('wd-a')
    end

    it 'keeps one lock per chat for good, so every caller waits on the same one' do
      epoch = open_browser('a', 'wd-a')
      lock = owner.op_lock('a')
      owner.reap(now: owner.clock + described_class::IDLE_LIMIT + 1)
      owner.release('a', epoch)
      replace('a')
      expect(owner.op_lock('a')).to be(lock)
    end
  end

  describe '.observe' do
    before { allow(owner).to receive(:observe).and_call_original }

    it 'asks web_navigator in the Python container, with no app' do
      allow(Monadic::Shell).to receive(:exec)
        .and_return(['out {"success": true, "sessions": ["x"], "max_sessions": 3}', "", double(success?: true)])
      expect(owner.observe).to eq(sessions: ['x'], max: 3)
      expect(Monadic::Shell).to have_received(:exec)
        .with(container: :python, argv: %w[web_navigator.py --action status], timeout: described_class::STATUS_TIMEOUT)
    end

    it 'is nil when Selenium cannot be asked or reports no slots' do
      owner.runner = ->(_, _) { '{"success": false, "error": "refused"}' }
      expect(owner.observe).to be_nil
      owner.runner = ->(_, _) { '{"success": true, "sessions": [], "max_sessions": 0}' }
      expect(owner.observe).to be_nil
      owner.runner = ->(_, _) { raise Monadic::Shell::TimedOut, 'slow' }
      expect(owner.observe).to be_nil
    end
  end

  # The browser tools, through a fake send_command (private, as in
  # MonadicApp) and a fake Python container for BrowserOwner's own
  # commands; both write to one log.
  describe 'the browser tools' do
    let(:log) { [] }
    let(:app) do
      commands = log
      Class.new do
        include MonadicSharedTools::WebAutomation
        attr_accessor :on_action

        define_method(:commands) { commands }

        def check_selenium_or_error = nil

        private

        def send_command(command:, container:)
          commands << command
          return '{"success": true, "session_id": "wd-new", "screenshot": null}' if command.include?('--action start')

          on_action&.call
          '{"success": true}'
        end
      end.new
    end
    let(:stop_reply) { '{"success": true}' }

    # The work's chat and epoch, as a chat scope keeps them from when the
    # chat started (EgressGuard).
    let(:session) { { chat_id: 'a' } }

    around do |example|
      key = Monadic::Utils::Privacy::EgressGuard::CHAT_KEY
      Fiber[key] = Monadic::Utils::Privacy::EgressGuard::Scope.of(session)
      example.run
    ensure
      Fiber[key] = nil
    end

    before do
      allow(owner).to receive(:close_later)
      owner.runner = lambda do |args, _|
        log << "web_navigator.py #{args.join(' ')}"
        stop_reply
      end
    end

    it 'closes the old browser before a new start' do
      open_browser('a', 'wd-old')
      app.start_browser(url: 'https://example.com')
      stop = log.index { |c| c.include?('--action stop') && c.include?('wd-old') }
      start = log.index { |c| c.include?('--action start') }
      expect(stop).to be < start
      expect(owner.session_for('a', owner.epoch('a'))).to eq('wd-new')
    end

    it "sends every action to the chat's own session, one command each" do
      open_browser('a', 'wd-a')
      app.browser_navigate(url: 'https://example.com')
      app.browser_back
      expect(log.size).to eq(2)
      expect(log[0]).to include('--action navigate').and include('--managed --session-id wd-a')
      expect(log[1]).to include('--action back').and include('--managed --session-id wd-a')
    end

    it 'does not hand back what an action saw after the chat was replaced' do
      open_browser('a', 'wd-a')
      app.on_action = -> { replace('a') }
      result = app.browser_navigate(url: 'https://example.com')
      expect(result[:error_code]).to eq('browser_replaced')
    end

    context 'when the close fails' do
      let(:stop_reply) { '{"success": false}' }

      it 'gives the browser up and says so' do
        epoch = open_browser('a', 'wd-a')
        result = app.stop_browser
        expect(result[:success]).to be(false)
        expect(owner.session_for('a', epoch)).to be_nil
      end
    end

    it 'refuses the browser in a Private chat without a command' do
      allow(Monadic::History::Policy).to receive(:current_work_private?).and_return(true)
      expect(app.start_browser(url: 'https://example.com')[:success]).to be(false)
      expect(app.capture_viewport_screenshots(url: 'https://example.com')[:success]).to be(false)
      expect(log).to be_empty
    end

    it 'refuses work that began before the chat was replaced, even after the chat comes back' do
      open_browser('a', 'wd-a')
      replace('a') # the work's scope still holds the epoch it began in
      expect(app.start_browser(url: 'https://example.com')[:error_code]).to eq('browser_replaced')
      expect(app.browser_back[:error_code]).to eq('browser_replaced')
      expect(app.stop_browser[:error_code]).to eq('browser_replaced')
      expect(log).to be_empty
    end

    it 'says so when Selenium cannot be asked' do
      allow(owner).to receive(:observe).and_return(nil)
      expect(app.start_browser(url: 'https://example.com')[:error_code]).to eq('browser_unavailable')
      expect(log).to be_empty
    end
  end
end
