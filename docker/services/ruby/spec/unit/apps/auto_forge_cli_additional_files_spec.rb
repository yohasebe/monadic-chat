# frozen_string_literal: true

require_relative '../../spec_helper'
require 'tmpdir'

require_relative '../../../apps/auto_forge/auto_forge_tools'

RSpec.describe 'AutoForge CLI optional files' do
  let(:helper_class) do
    Class.new do
      include AutoForgeTools

      def initialize
        @context = {}
      end
    end
  end

  let(:helper) { helper_class.new }

  describe '#suggest_cli_additional_files' do
    it 'suggests README and custom option when the script has no config or external deps' do
      Dir.mktmpdir do |dir|
        script_path = File.join(dir, 'runtimes_lister.py')
        File.write(script_path, <<~PY)
          #!/usr/bin/env python3
          import sys

          def main():
            print("Python " + sys.version)

          if __name__ == '__main__':
            main()
        PY

        suggestions = helper.send(:suggest_cli_additional_files, dir, 'runtimes_lister.py')
        keys = suggestions.map { |entry| entry.is_a?(Hash) ? entry[:key] : entry }
        expect(keys).to include(:readme, :custom)
      end
    end

    it 'suggests config and dependencies when the script requires them' do
      Dir.mktmpdir do |dir|
        script_path = File.join(dir, 'reporter.py')
        File.write(script_path, <<~PY)
          #!/usr/bin/env python3
          import configparser
          import requests

          def load_config(path):
            parser = configparser.ConfigParser()
            parser.read(path)
            return parser

          def fetch(url):
            return requests.get(url, timeout=10)

          if __name__ == '__main__':
            load_config('config.ini')
            fetch('https://example.com')
        PY

        suggestions = helper.send(:suggest_cli_additional_files, dir, 'reporter.py')
        keys = suggestions.map { |entry| entry.is_a?(Hash) ? entry[:key] : entry }
        expect(keys).to include(:readme, :config, :dependencies, :custom)
      end
    end
  end

  describe '#generate_additional_file' do
    it 'creates a README for the active CLI project' do
      Dir.mktmpdir do |dir|
        script_path = File.join(dir, 'tool.py')
        File.write(script_path, "#!/usr/bin/env python3\nprint('ok')\n")

        helper.instance_variable_set(
          :@context,
          {
            auto_forge: {
              project_path: dir,
              project_type: 'cli',
              main_file: 'tool.py'
            }
          }
        )

        message = helper.generate_additional_file('file_type' => 'readme')
        expect(message).to include('✅ Created README.md')
        expect(File).to exist(File.join(dir, 'README.md'))
      end
    end

    it 'creates a custom file when file_name and instructions are provided' do
      Dir.mktmpdir do |dir|
        script_path = File.join(dir, 'tool.py')
        File.write(script_path, "#!/usr/bin/env python3\nprint('ok')\n")

        helper.instance_variable_set(
          :@context,
          {
            agent: :openai,
            auto_forge: {
              project_path: dir,
              project_type: 'cli',
              main_file: 'tool.py'
            }
          }
        )

        # Mock call_openai_code method which is used by resolve_text_generator
        allow(helper).to receive(:call_openai_code).and_return({ success: true, code: "Line one\nLine two" })

        message = helper.generate_additional_file(
          'file_name' => 'USAGE.md',
          'instructions' => 'Provide helpful usage notes.'
        )

        expect(message).to include('✅ Created USAGE.md')
        expect(File.read(File.join(dir, 'USAGE.md'))).to include('Line one')
      end
    end

    it 'rejects unsafe file names' do
      Dir.mktmpdir do |dir|
        helper.instance_variable_set(
          :@context,
          {
            auto_forge: {
              project_path: dir,
              project_type: 'cli',
              main_file: 'tool.py'
            }
          }
        )

        message = helper.generate_additional_file(
          'file_name' => '../secret.txt',
          'instructions' => 'Should not work'
        )

        expect(message).to include('❌ Failed')
      end
    end
  end
end
