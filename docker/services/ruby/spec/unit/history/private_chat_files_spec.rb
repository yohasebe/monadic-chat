# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "securerandom"
require "rbconfig"
require "fileutils"

# A whole chat, from the page's WebSocket to the answer it shows, run by the
# web app booted from config.ru in a child process with a home of its own.
# The provider is replaced by an answer that does what an answer's tools do
# (a command, printed lines, a thread that dies of an exception, the file
# tool), and the page also sends an upload. The words of the chat carry a
# marker; afterwards every file under that home is read for it.
#
# A normal chat is the positive control: the marker is found in the
# history, the logs, the output and the shared folder, and writes are seen.
# A Private chat leaves the marker nowhere and writes nothing from the
# moment it is Private, also when the process is killed in the middle of an
# answer (no ensure or at_exit runs) and after the app boots again on what
# was left.
RSpec.describe "Files of a Private chat" do
  def app_root
    File.expand_path("../../..", __dir__)
  end

  def child_script
    <<~'RUBY'
    require "rack"
    require "rack/mock_request"
    require "tempfile"
    require "json"

    mode = ENV.fetch("PROBE_MODE")
    mark = ENV.fetch("PROBE_MARK")
    kill_midway = ENV["PROBE_KILL"] == "1"
    home = File.realpath(Dir.home)

    app, = Rack::Builder.parse_file("config.ru")
    exit!(0) if mode == "boot"

    control = IO.for_fd(3, autoclose: false)
    control.sync = true
    report = ->(tag, data) { control.puts("#{tag} #{data.to_json}") }

    # Every write under the home, by Ruby or SQLite, recorded from the
    # moment the chat is Private (for a normal chat, from the same point).
    writes = []
    recording = false
    inside = lambda do |path|
      full = File.expand_path(path.to_s)
      dir = File.dirname(full)
      dir = File.dirname(dir) until File.exist?(dir) || dir == "/"
      real = File.join(File.realpath(dir), full.delete_prefix(dir))
      real.start_with?(home) ? real.delete_prefix(home) : nil
    rescue StandardError
      nil
    end
    note = lambda do |op, path|
      next unless recording && path

      rel = inside.call(path)
      writes << [op, rel] if rel
    end
    writing = lambda do |how|
      case how
      when nil then false
      when Integer then (how & (File::WRONLY | File::RDWR | File::CREAT | File::APPEND | File::TRUNC)) != 0
      else how.to_s.match?(/[wa+]/)
      end
    end
    File.singleton_class.prepend(Module.new do
      define_method(:open) { |path, *args, **kw, &blk| note.call(:open, path) if writing.call(args[0] || kw[:mode]); super(path, *args, **kw, &blk) }
      define_method(:new) { |path, *args, **kw, &blk| note.call(:new, path) if path.is_a?(String) && writing.call(args[0] || kw[:mode]); super(path, *args, **kw, &blk) }
      %i[write binwrite].each { |m| define_method(m) { |path, *args, **kw| note.call(m, path); super(path, *args, **kw) } }
      %i[rename link symlink].each { |m| define_method(m) { |from, to| note.call(m, to); super(from, to) } }
    end)
    IO.singleton_class.prepend(Module.new do
      define_method(:sysopen) { |path, *args| note.call(:sysopen, path) if writing.call(args[0]); super(path, *args) }
      %i[write binwrite].each { |m| define_method(m) { |path, *args, **kw| note.call(m, path); super(path, *args, **kw) } }
      define_method(:copy_stream) { |src, dst, *args| note.call(:copy_stream, dst) if dst.is_a?(String); super(src, dst, *args) }
    end)
    Dir.singleton_class.prepend(Module.new do
      define_method(:mkdir) { |path, *args| note.call(:mkdir, path); super(path, *args) }
    end)
    File.prepend(Module.new do
      %i[write syswrite write_nonblock].each { |m| define_method(m) { |*args, **kw| note.call(m, path); super(*args, **kw) } }
    end)
    # SQLite writes an open database itself, past Ruby: what is asked of a
    # database under the home is recorded instead (a write is a statement
    # that is not a read).
    SQLite3::Database.prepend(Module.new do
      define_method(:initialize) do |path, *args, **kw, &blk|
        note.call(:sqlite, path)
        @probe_path = inside.call(path)
        super(path, *args, **kw, &blk)
      end
      %i[execute execute_batch].each do |m|
        define_method(m) do |sql, *args, **kw, &blk|
          verb = sql.to_s.strip[/\A\w+/].to_s.upcase
          writes << [:sql, "#{verb} #{@probe_path}"] if recording && @probe_path && !%w[SELECT PRAGMA].include?(verb)
          super(sql, *args, **kw, &blk)
        end
      end
    end)

    # Nothing runs in a container, and the Privacy service answers.
    require "monadic/utils/privacy/presidio_backend"
    Monadic::Utils::ContainerDependencies.singleton_class.prepend(Module.new do
      define_method(:ensure_services_async) { |*_args, **_kw| false }
    end)
    Monadic::Utils::Privacy::PresidioBackend.prepend(Module.new do
      define_method(:health) { true }
    end)

    # The provider's answer, and what an answer's tools do while it is
    # written, with the words of the chat being answered. Killed here, the
    # process is in the middle of the answer.
    app_name = "ChatPlusOpenAI"
    words = nil
    target = false
    APPS[app_name].singleton_class.prepend(Module.new do
      define_method(:api_request) do |_role, _session, &block|
        block&.call({ "type" => "fragment", "content" => "reply #{words}" })
        Monadic::Shell.capture(["echo", "command #{words}"])
        puts "stdout #{words}"
        warn "warning #{words}"
        Thread.new { raise "thread #{words}" }.join rescue nil
        tool = write_file_to_shared_folder(filepath: "note-#{words}.txt", content: "file #{words}")
        report.call("TOOL", { "written" => tool[:success] }) if target
        if kill_midway && target
          STDOUT.flush
          STDERR.flush
          $stderr.flush
          report.call("MIDWAY", { "writes" => writes })
          sleep
        end
        [{ "choices" => [{ "message" => { "role" => "assistant", "content" => "reply #{words}" }, "finish_reason" => "stop" }] }]
      end
    end)

    require "async"
    require "async/http/endpoint"
    require "async/http/server"
    require "async/websocket/client"
    require "protocol/rack"
    require "socket"

    out = {}
    port = (probe = TCPServer.new("127.0.0.1", 0)).addr[1]
    probe.close
    origin = "http://127.0.0.1:#{port}"

    # One chat in a tab of its own, as the page has it: the app, the filter
    # (for a Private chat), a message, the answer shown, an upload.
    chat = lambda do |task, said, private:, watched:|
      tab = "probe-#{rand(1_000_000)}"
      words = said
      target = watched
      result = {}
      Async::WebSocket::Client.connect(Async::HTTP::Endpoint.parse("#{origin}/?tab_id=#{tab}"), headers: [["origin", origin]]) do |conn|
        send = ->(obj) { conn.write(obj.to_json); conn.flush }
        wait_for = lambda do |type|
          task.with_timeout(30) do
            loop do
              msg = JSON.parse(conn.read.to_str)
              break msg if msg["type"] == type
            end
          end
        end
        send.call({ "message" => "UPDATE_PARAMS", "params" => { "app_name" => app_name } })
        send.call({ "message" => "PING" })
        wait_for.call("pong")
        # Recorded from before the filter is asked for: making the chat
        # Private writes nothing either.
        recording = watched
        if private
          send.call({ "message" => "PRIVACY_TOGGLE", "enabled" => true })
          result["toggle"] = wait_for.call("privacy_toggle_ack").slice("enabled", "private")
        end
        send.call({ "message" => "hello #{said}", "app_name" => app_name })
        wait_for.call("streaming_complete")
        send.call({ "message" => "HTML" })
        result["shown"] = wait_for.call("html").to_json.include?("reply #{said}")

        made = []
        factory = ->(filename, _type) { Tempfile.new(["RackMultipart", File.extname(filename.to_s)]).tap { |f| made << f } }
        body = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"up-#{said}.mp4\"\r\n" \
               "Content-Type: video/mp4\r\n\r\nupload #{said}\r\n--B--\r\n"
        res = Rack::MockRequest.new(app).post("#{origin}/attachments?tab_id=#{tab}",
                                              input: body, "CONTENT_TYPE" => "multipart/form-data; boundary=B",
                                              "HTTP_HOST" => "127.0.0.1:#{port}", "HTTP_ORIGIN" => origin,
                                              "rack.multipart.tempfile_factory" => factory)
        result["upload"] = { "status" => res.status, "body_read" => !made.empty? }

        # A conversation imported from a file (Import), in this tab.
        conversation = { "parameters" => { "app_name" => app_name },
                         "messages" => [{ "role" => "user", "text" => "imported #{said}" }] }.to_json
        body = "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"chat-#{said}.json\"\r\n" \
               "Content-Type: application/json\r\n\r\n#{conversation}\r\n--B--\r\n"
        res = Rack::MockRequest.new(app).post("#{origin}/load?tab_id=#{tab}",
                                              input: body, "CONTENT_TYPE" => "multipart/form-data; boundary=B",
                                              "HTTP_HOST" => "127.0.0.1:#{port}", "HTTP_ORIGIN" => origin)
        result["import"] = { "status" => res.status, "staged" => JSON.parse(res.body)["success"] == true }
      end
      recording = false
      result
    end

    Async do |task|
      server = task.async { Async::HTTP::Server.new(Protocol::Rack::Adapter.new(app), Async::HTTP::Endpoint.parse(origin)).run }
      task.sleep(0.2)
      if mode == "private"
        # A normal chat first, so the history is there and open.
        out["earlier"] = chat.call(task, ENV.fetch("PROBE_EARLIER"), private: false, watched: false)
        out.merge!(chat.call(task, mark, private: true, watched: true))
      else
        out.merge!(chat.call(task, mark, private: false, watched: true))
      end
      server.stop
    end
    out["writes"] = writes
    STDOUT.flush
    STDERR.flush
    $stderr.flush
    report.call("DONE", out)
    exit!(0)
    RUBY
  end

  # A home with EXTRA_LOGGING on, a docker that runs nothing, and an op
  # that reads nothing.
  def make_home
    home = Dir.mktmpdir("private-chat-home")
    FileUtils.mkdir_p([File.join(home, "tmp"), File.join(home, "monadic", "config"), File.join(home, "bin")])
    File.write(File.join(home, "monadic", "config", "env"), "EXTRA_LOGGING=true\n")
    %w[docker op].each do |tool|
      path = File.join(home, "bin", tool)
      File.write(path, "#!/bin/sh\nexit 1\n")
      File.chmod(0o755, path)
    end
    home
  end

  def child_env(home, mode:, mark: nil, earlier: nil, kill: false)
    { "HOME" => home, "TMPDIR" => File.join(home, "tmp"), "IN_CONTAINER" => "false",
      "EXTRA_LOGGING" => "true", "MONADIC_HISTORY" => nil,
      "MONADIC_OP_CLI" => File.join(home, "bin", "op"),
      "PATH" => "#{File.join(home, 'bin')}:#{ENV.fetch('PATH')}",
      "PROBE_MODE" => mode, "PROBE_MARK" => mark.to_s, "PROBE_EARLIER" => earlier.to_s, "PROBE_KILL" => kill ? "1" : "0" }
  end

  # Starts a chat in a child; with kill, the child is killed once it is in
  # the middle of the answer. Output and control lines are kept outside the
  # home.
  def start_chat(mode:, kill:)
    run = { home: make_home, outside: Dir.mktmpdir("private-chat-out"), mark: "MARK#{SecureRandom.hex(16)}",
            earlier: "EARLIER#{SecureRandom.hex(16)}", kill: kill }
    run[:control], writer = IO.pipe
    run[:pid] = Process.spawn(child_env(run[:home], mode: mode, mark: run[:mark], earlier: run[:earlier], kill: kill),
                              RbConfig.ruby, "-Ilib", "-e", child_script,
                              chdir: app_root, out: File.join(run[:outside], "stdout"),
                              err: File.join(run[:outside], "stderr"), 3 => writer, in: File::NULL)
    writer.close
    run
  end

  def finish_chat(run)
    lines = {}
    deadline = Time.now + 180
    until lines.key?("DONE") || lines.key?("MIDWAY")
      raise "the chat did not finish:\n#{File.read(File.join(run[:outside], 'stderr')).lines.last(20).join}" if Time.now > deadline
      ready = IO.select([run[:control]], nil, nil, 1)
      next unless ready

      line = run[:control].gets
      if line.nil?
        _, status = Process.wait2(run[:pid])
        run[:reaped] = true
        raise "the child ended early (#{status.inspect}):\n#{File.read(File.join(run[:outside], 'stderr')).lines.last(20).join}"
      end

      tag, json = line.split(" ", 2)
      lines[tag] = JSON.parse(json)
    end
    Process.kill(:KILL, run[:pid]) if lines.key?("MIDWAY")
    _, status = Process.wait2(run[:pid])
    run[:reaped] = true
    run.merge(lines: lines, status: status)
  ensure
    run[:control]&.close
  end

  # Every file under the home holding the marker (as UTF-8 or UTF-16), in
  # its content or its name. Every file must be readable.
  def files_with(mark, home)
    forms = [mark, mark.encode("UTF-16LE"), mark.encode("UTF-16BE")].map { |f| f.dup.force_encoding("BINARY") }
    found = []
    unread = []
    Dir.glob("**/*", File::FNM_DOTMATCH, base: home).each do |rel|
      path = File.join(home, rel)
      next unless File.file?(path)

      begin
        bytes = File.binread(path)
      rescue SystemCallError
        unread << rel
        next
      end
      found << rel if rel.include?(mark) || forms.any? { |f| bytes.include?(f) }
    end
    raise "files not read: #{unread}" unless unread.empty?

    found
  end

  def printed(run, stream)
    File.binread(File.join(run[:outside], stream)).scan(run[:mark]).size
  end

  # Each child is kept here as soon as it starts, so that a failure while
  # the others start or finish leaves none of them behind.
  before(:all) do
    @started = {}
    { normal: ["normal", false], private: ["private", false],
      normal_killed: ["normal", true], private_killed: ["private", true] }.each do |name, (mode, kill)|
      @started[name] = start_chat(mode: mode, kill: kill)
    end
    @runs = @started.transform_values { |run| finish_chat(run) }
  end

  # Also when a chat failed: no child is left running, no home is left.
  after(:all) do
    (@started || {}).each_value do |run|
      unless run[:reaped]
        begin
          Process.kill(:KILL, run[:pid])
          Process.wait(run[:pid])
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
      end
      FileUtils.rm_rf([run[:home], run[:outside]])
    end
  end

  describe "a normal chat (the positive control)" do
    let(:run) { @runs[:normal] }

    it "is kept in the history, the logs, the output and the shared folder" do
      done = run[:lines].fetch("DONE")
      expect(done["shown"]).to be(true)
      found = files_with(run[:mark], run[:home])
      expect(found.grep(%r{\Amonadic/state/history\.sqlite3})).not_to be_empty
      expect(found).to include("monadic/log/extra.log", "monadic/log/command.log", "monadic/data/note-#{run[:mark]}.txt")
      expect(printed(run, "stdout")).to be >= 1
      expect(printed(run, "stderr")).to be >= 2 # the warning and the thread's exception
      expect(done["writes"].map(&:last)).to include("/monadic/state/history.sqlite3", "/monadic/log/extra.log",
                                                    "INSERT /monadic/state/history.sqlite3")
      expect(run[:lines].fetch("TOOL")).to eq("written" => true)
      expect(done["upload"]["body_read"]).to be(true)
      expect(done["import"]).to eq("status" => 200, "staged" => true)
    end

    it "is still found where it was written when the process is killed in an answer" do
      killed = @runs[:normal_killed]
      expect(killed[:lines]).to have_key("MIDWAY")
      expect(killed[:status].termsig).to eq(Signal.list.fetch("KILL"))
      found = files_with(killed[:mark], killed[:home])
      expect(found.grep(%r{\Amonadic/state/history\.sqlite3})).not_to be_empty
      expect(found).to include("monadic/log/extra.log", "monadic/log/command.log")
      expect(printed(killed, "stderr")).to be >= 2
    end
  end

  describe "a Private chat" do
    let(:run) { @runs[:private] }

    # Each Private chat follows a normal one in another tab, so the history
    # is there and open; that chat is kept (found by the same scan).
    def earlier_kept(run)
      expect(run[:lines].values.last["earlier"] || run[:lines].fetch("MIDWAY")).to be_truthy
      expect(files_with(run[:earlier], run[:home]).grep(%r{\Amonadic/state/history\.sqlite3})).not_to be_empty
    end

    it "is answered and shown as a normal one" do
      done = run[:lines].fetch("DONE")
      expect(done["earlier"]["shown"]).to be(true)
      expect(done["toggle"]).to eq("enabled" => true, "private" => true)
      expect(done["shown"]).to be(true)
      expect(done["import"]).to eq("status" => 200, "staged" => true)
    end

    it "leaves the marker in no file and in no output, beside a kept normal chat" do
      earlier_kept(run)
      expect(files_with(run[:mark], run[:home])).to eq([])
      expect(printed(run, "stdout")).to eq(0)
      expect(printed(run, "stderr")).to eq(0)
    end

    it "writes nothing once it is Private, not even a file it removes again" do
      expect(run[:lines].fetch("DONE")["writes"]).to eq([])
      expect(run[:lines].fetch("TOOL")).to eq("written" => false)
      expect(run[:lines].fetch("DONE")["upload"]).to eq("status" => 403, "body_read" => false)
    end

    it "leaves nothing when the process is killed in an answer, nor once the app boots again" do
      killed = @runs[:private_killed]
      expect(killed[:lines].fetch("MIDWAY")["writes"]).to eq([])
      expect(killed[:status].termsig).to eq(Signal.list.fetch("KILL"))
      earlier_kept(killed)
      expect(files_with(killed[:mark], killed[:home])).to eq([])
      expect(printed(killed, "stdout") + printed(killed, "stderr")).to eq(0)

      _, status = Process.wait2(Process.spawn(child_env(killed[:home], mode: "boot"), RbConfig.ruby, "-Ilib", "-e", child_script,
                                              chdir: app_root, out: File::NULL, err: File::NULL, in: File::NULL))
      expect(status.exitstatus).to eq(0)
      earlier_kept(killed)
      expect(files_with(killed[:mark], killed[:home])).to eq([])
    end
  end
end
