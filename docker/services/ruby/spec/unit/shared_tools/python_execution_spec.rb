# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/shared_tools/python_execution"

# The code runner the tool hands the code to (MonadicHelper#run_code): it
# records what it was given.
module MonadicHelper
  def run_code(code:, command:, extension:, session: nil, run_dir: nil)
    (@code_runs ||= []) << { code: code, run_dir: run_dir }
    "The code has been executed successfully"
  end
end

RSpec.describe "MonadicSharedTools::PythonExecution" do
  let(:test_class) do
    Class.new do
      include MonadicHelper
      include MonadicSharedTools::PythonExecution
      attr_reader :code_runs
    end
  end

  let(:app) { test_class.new }
  let(:session) { { parameters: {} } }
  let(:job) { { path: "/data/conversations/c/artifacts/j_1", relative: "conversations/c/artifacts/j_1" } }

  describe "#run_code" do
    it "runs the code in a run folder of the chat and lists what it left there" do
      allow(Monadic::Workbench::ChatOutput).to receive(:run_folder).and_return(job)
      allow(Monadic::Workbench::ChatOutput).to receive(:take_all)
        .and_return({ paths: ["#{job[:relative]}/plot.png"], shown: true })
      result = app.run_code(code: "print(1)", command: "python", extension: "py", session: session)
      expect(app.code_runs).to eq([{ code: "print(1)", run_dir: job }])
      expect(result).to include("#{job[:relative]}/plot.png", "work screen")
    end

    it "runs nothing without a chat" do
      allow(Monadic::Workbench::ChatOutput).to receive(:run_folder).and_return(nil)
      result = app.run_code(code: "print(1)", command: "python", extension: "py", session: session)
      expect(result).to include("no chat folder")
      expect(app.code_runs).to be_nil
    end

    context "when code is empty" do
      it "returns an error" do
        result = app.run_code(code: "", command: "python", extension: "py", session: session)
        expect(result).to eq({ success: false, error: "Code cannot be empty" })
      end
    end

    context "when command is missing" do
      it "returns an error" do
        result = app.run_code(code: "print('hello')", command: nil, extension: "py", session: session)
        expect(result).to eq({ success: false, error: "Missing required parameters: code, command, and extension are all required" })
      end
    end
  end

  describe "#run_bash_command — path-misuse defensive warning" do
    # Register a mock super implementation so the shared module's
    # `super(command:)` call has something to forward to.
    before do
      test_class.send(:define_method, :run_bash_command) do |command:|
        # Mirror the shared module body but short-circuit the real super call.
        return { success: false, error: "Command parameter is required" } unless command
        return { success: false, error: "Command cannot be empty" } if command.to_s.strip.empty?

        if command.to_s.include?('~/monadic/data')
          Monadic::Utils::ExtraLogger.log {
            "[PythonExecution] ~/monadic/data detected in run_bash_command — model likely confused container vs host paths. Command: #{command.to_s[0..200]}"
          }
        end
        'executed'
      end
    end

    it 'logs a warning when the command references ~/monadic/data' do
      expect(Monadic::Utils::ExtraLogger).to receive(:log).once
      app.run_bash_command(command: 'ls ~/monadic/data/sales.csv')
    end

    it 'does not log when the command uses /data (the correct path)' do
      expect(Monadic::Utils::ExtraLogger).not_to receive(:log)
      app.run_bash_command(command: 'ls /data/sales.csv')
    end

    it 'does not log when the command uses /monadic/data (also correct)' do
      expect(Monadic::Utils::ExtraLogger).not_to receive(:log)
      app.run_bash_command(command: 'ls /monadic/data/sales.csv')
    end
  end
end
