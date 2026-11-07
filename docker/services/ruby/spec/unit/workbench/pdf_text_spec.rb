# frozen_string_literal: true

require_relative "../../spec_helper"
require "tmpdir"
require "json"
require_relative "../../../lib/monadic/workbench/pdf_text"

# Reading the text of a PDF's pages in the Python container, through a
# docker that only acts the part: what each run does is set by the test.
RSpec.describe Monadic::Workbench::PdfText do
  let(:pdf_text) { described_class }

  around do |example|
    Dir.mktmpdir("pdf-text-spec") do |dir|
      @dir = dir
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "docker"), <<~'SH')
        #!/bin/sh
        # exec [-i] [-w dir] [-e VAR=val] name argv...
        echo "$*" >> "$FAKE_DIR/calls"
        shift
        [ "$1" = "-i" ] && shift
        while [ "$1" = "-w" ] || [ "$1" = "-e" ]; do shift 2; done
        shift
        if [ "$1" = "sh" ]; then
          [ -f "$FAKE_DIR/stop_sleep" ] && sleep "$(cat "$FAKE_DIR/stop_sleep")"
          if [ "$(cat "$FAKE_DIR/mode")" = "down" ]; then
            echo "Error response from daemon: container monadic-chat-python-container is not running" >&2
            exit 1
          fi
          cat "$FAKE_DIR/stop" 2>/dev/null || echo "left=0"
          exit 0
        fi
        cat > "$FAKE_DIR/stdin"
        mode=$(cat "$FAKE_DIR/mode")
        case "$mode" in
          ok) cat "$FAKE_DIR/out" ;;
          slow) sleep 30 ;;
          flood) yes aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
          down) echo "Error response from daemon: container monadic-chat-python-container is not running" >&2; exit 1 ;;
          fail) echo "Error: ValueError" >&2; exit 1 ;;
        esac
      SH
      File.chmod(0o755, File.join(bin, "docker"))
      path = ENV["PATH"]
      ENV["PATH"] = "#{bin}:#{path}"
      ENV["FAKE_DIR"] = dir
      pdf_text.reset!
      example.run
    ensure
      ENV["PATH"] = path
      ENV.delete("FAKE_DIR")
      pdf_text.reset!
    end
  end

  def runs(mode, out = nil)
    File.write(File.join(@dir, "mode"), mode)
    File.write(File.join(@dir, "out"), out.to_s)
  end

  def lines(*objects)
    objects.map { |o| JSON.generate(o) }.join("\n") + "\n"
  end

  def soon(seconds = 10)
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
  end

  def calls
    File.exist?(File.join(@dir, "calls")) ? File.readlines(File.join(@dir, "calls"), chomp: true) : []
  end

  it "gives the pages the script wrote, after giving it the bytes on its stdin" do
    runs("ok", lines({ page: 2, text: "two", cut: false }, { page: 3, text: "thr", cut: true },
                     { done: true, total_pages: 9, stopped_at: nil }))
    got = pdf_text.extract("%PDF-1.4 bytes", first: 2, last: 3, deadline: soon)
    expect(got.pages).to eq([{ page: 2, text: "two", cut: false }, { page: 3, text: "thr", cut: true }])
    expect(got.total_pages).to eq(9)
    expect(File.binread(File.join(@dir, "stdin"))).to eq("%PDF-1.4 bytes")
    run = calls.first
    expect(run).to include("exec -i", "MONADIC_RUN_ID=", "monadic-chat-python-container", "timeout -s KILL 15 python3",
                           "--stdin --first-page 2 --last-page 3 --max-chars 64000 --max-memory-mb 768")
    expect(run).not_to include("%PDF")
    expect(pdf_text.busy).to eq([0, 0])
  end

  it "stops at the PDF's last page and says where the characters ran out" do
    runs("ok", lines({ page: 1, text: "a", cut: false }, { done: true, total_pages: 5, stopped_at: 2 }))
    got = pdf_text.extract("%PDF", first: 1, last: 100, deadline: soon)
    expect(got.pages.size).to eq(1)
    expect(got.stopped_at).to eq(2)
    runs("ok", lines({ page: 1, text: "", cut: false }, { page: 2, text: "b", cut: false },
                     { done: true, total_pages: 2, stopped_at: nil }))
    expect(pdf_text.extract("%PDF", first: 1, last: 100, deadline: soon).pages.map { |p| p[:page] }).to eq([1, 2])
  end

  def stop_calls
    File.exist?(File.join(@dir, "calls")) ? File.read(File.join(@dir, "calls")).scan(/ sh -c /).size : 0
  end

  it "checks that a run that failed is gone, and keeps its slot when that cannot be told" do
    runs("fail")
    File.write(File.join(@dir, "stop"), "left=1\n")
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }.to raise_error(described_class::Unavailable)
    expect(stop_calls).to eq(1)
    expect(pdf_text.busy).to eq([0, 1])
  end

  it "starts nothing once the time is out, also with a slot free" do
    runs("ok", lines({ page: 1, text: "a", cut: false }, { done: true, total_pages: 1, stopped_at: nil }))
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(-1)) }
      .to raise_error(described_class::Unavailable) { |e| expect(e.reason).to eq("busy") }
    expect(calls).to be_empty
  end

  it "checks a run not known to be gone only as time allows, and by one caller at a time" do
    runs("slow")
    File.write(File.join(@dir, "stop"), "left=1\n")
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(0.3)) }.to raise_error(described_class::Unavailable)
    stub_const("Monadic::Workbench::PdfText::SLOTS", 1)
    before = stop_calls
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(0.3)) }.to raise_error(described_class::Unavailable)
    expect(stop_calls).to eq(before)
    File.write(File.join(@dir, "stop_sleep"), "1")
    two = Array.new(2) do
      Thread.new do
        pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(3))
      rescue described_class::Unavailable => e
        e.reason
      end
    end
    two.each { |t| t.join(10) }
    expect(stop_calls).to eq(before + 1)
  end

  it "gives back every run it took to check, also when it is stopped while checking the first" do
    runs("slow")
    File.write(File.join(@dir, "stop"), "left=1\n")
    2.times do
      expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(0.3)) }.to raise_error(described_class::Unavailable)
    end
    expect(pdf_text.busy).to eq([0, 2])
    File.write(File.join(@dir, "stop_sleep"), "5")
    before = stop_calls
    checking = Thread.new { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(20)) }
    sleep 0.05 until stop_calls > before
    stopping = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    checking.kill
    checking.join(10)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - stopping).to be < 2
    expect(pdf_text.instance_variable_get(:@checking)).to be_empty
    File.delete(File.join(@dir, "stop_sleep"))
    File.write(File.join(@dir, "stop"), "left=0\n")
    runs("ok", lines({ page: 1, text: "a", cut: false }, { done: true, total_pages: 1, stopped_at: nil }))
    expect(pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon).pages.size).to eq(1)
    expect(pdf_text.busy).to eq([0, 0])
  end

  it "gives up a check that does not end, within the time given for it" do
    File.write(File.join(@dir, "mode"), "ok")
    File.write(File.join(@dir, "stop_sleep"), "30")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    gone = Monadic::Shell.stop_and_confirm("monadic-chat-python-container", "a" * 32, timeout: 1)
    expect(gone).to be(false)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1.5
  end

  describe "what docker says of a container" do
    let(:name) { "monadic-chat-python-container" }

    {
      "Error response from daemon: container monadic-chat-python-container is not running" => true,
      "Error response from daemon: container 3f2a9b1c4d5e6f708192a3b4 is not running" => true,
      "Error response from daemon: No such container: monadic-chat-python-container" => true,
      "Error: Docker daemon is not running" => false,
      "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" => false,
      "permission denied while trying to connect to the Docker daemon socket" => false,
      "Error response from daemon: No such container: monadic-chat-ruby-container" => false,
      "Error response from daemon: container other-container is not running" => false,
      "the server is not running" => false
    }.each do |said, gone|
      it "takes #{said.inspect} as #{gone ? '' : 'not '}saying nothing runs in it" do
        expect(Monadic::Shell.not_running?("#{said}\n", name)).to be(gone)
      end
    end
  end

  it "leaves no thread of a run behind when it is stopped" do
    runs("slow")
    before = Thread.list.size
    reading = Thread.new { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }
    sleep 0.05 until calls.any?
    reading.kill
    reading.join(10)
    sleep 0.1
    expect(Thread.list.size).to eq(before)
  end

  {
    "a last line that is true" => "true",
    "a last line that is null" => "null",
    "a last line that is a number" => "3",
    "a last line that is a string" => '"done"',
    "a last line that is a list" => "[1]",
    "two last lines" => [JSON.generate({ done: true, total_pages: 1, stopped_at: nil }),
                         JSON.generate({ done: true, total_pages: 1, stopped_at: nil })].join("\n"),
    "bytes that are not UTF-8" => "{\"page\": 1, \"text\": \"\xFF\", \"cut\": false}\n" +
                                   JSON.generate({ done: true, total_pages: 1, stopped_at: nil })
  }.each do |what, out|
    it "takes nothing when what came back has #{what}" do
      runs("ok", "#{out}\n")
      expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }
        .to raise_error(described_class::Unavailable) { |e| expect(e.reason).to eq("pdf_text_unavailable") }
    end
  end

  {
    "a page missing" => [{ page: 1, text: "a", cut: false }, { page: 3, text: "c", cut: false },
                         { done: true, total_pages: 3, stopped_at: nil }],
    "pages out of order" => [{ page: 2, text: "b", cut: false }, { page: 1, text: "a", cut: false },
                             { done: true, total_pages: 2, stopped_at: nil }],
    "no last line" => [{ page: 1, text: "a", cut: false }, { page: 2, text: "b", cut: false }],
    "more after the last line" => [{ page: 1, text: "a", cut: false }, { done: true, total_pages: 1, stopped_at: nil },
                                   { page: 2, text: "b", cut: false }],
    "a text that is not text" => [{ page: 1, text: 5, cut: false }, { done: true, total_pages: 1, stopped_at: nil }],
    "a page number that is not a whole number" => [{ page: 1.0, text: "a", cut: false },
                                                  { done: true, total_pages: 1, stopped_at: nil }],
    "a cut page before another" => [{ page: 1, text: "a", cut: true }, { page: 2, text: "b", cut: false },
                                    { done: true, total_pages: 2, stopped_at: nil }],
    "more characters than asked" => [{ page: 1, text: "x" * 11, cut: false }, { done: true, total_pages: 1, stopped_at: nil }]
  }.each do |what, written|
    it "takes nothing when what came back has #{what}" do
      runs("ok", lines(*written))
      expect { pdf_text.extract("%PDF", first: 1, last: 2, deadline: soon, chars: 10) }
        .to raise_error(described_class::Unavailable) { |e| expect(e.reason).to eq("pdf_text_unavailable") }
    end
  end

  it "takes a run that failed or a container that is not running as no text, and starts nothing" do
    runs("down")
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }
      .to raise_error(described_class::Unavailable, /not running/)
    # Nothing runs in a container that is not running: the slot is free.
    expect(pdf_text.busy).to eq([0, 0])
    runs("fail")
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }
      .to raise_error(described_class::Unavailable, /could not be read/)
    expect(calls.grep(/ start /)).to be_empty
    expect(pdf_text.busy).to eq([0, 0])
  end

  it "stops a run past its time, and what it started in the container, then frees its slot" do
    runs("slow")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(0.5)) }
      .to raise_error(described_class::Unavailable, /too long/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 8
    expect(File.read(File.join(@dir, "calls"))).to match(/exec monadic-chat-python-container sh -c .*left=.* sh \h{32}$/m)
    expect(pdf_text.busy).to eq([0, 0])
  end

  it "stops a run that writes too much" do
    runs("flood")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }
      .to raise_error(described_class::Unavailable, /too large/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
    expect(pdf_text.busy).to eq([0, 0])
  end

  it "keeps the slot of a run not known to be gone until it is checked again" do
    runs("slow")
    File.write(File.join(@dir, "stop"), "left=1\n")
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(0.3)) }.to raise_error(described_class::Unavailable)
    expect(pdf_text.busy).to eq([0, 1])
    stub_const("Monadic::Workbench::PdfText::SLOTS", 1)
    runs("ok", lines({ page: 1, text: "a", cut: false }, { done: true, total_pages: 1, stopped_at: nil }))
    expect { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon(0.3)) }
      .to raise_error(described_class::Unavailable) { |e| expect(e.reason).to eq("busy") }
    File.write(File.join(@dir, "stop"), "left=0\n")
    expect(pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon).pages.size).to eq(1)
    expect(pdf_text.busy).to eq([0, 0])
  end

  it "frees the slot of a reading stopped by Cancel once what it started is gone" do
    runs("slow")
    reading = Thread.new { pdf_text.extract("%PDF", first: 1, last: 1, deadline: soon) }
    sleep 0.05 until calls.any?
    reading.kill
    reading.join(10)
    expect(reading).not_to be_alive
    expect(File.read(File.join(@dir, "calls"))).to match(/exec monadic-chat-python-container sh -c /)
    expect(pdf_text.busy).to eq([0, 0])
  end
end
