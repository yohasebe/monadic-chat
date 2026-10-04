# frozen_string_literal: true

require 'open3'

RSpec.describe 'Docker disk usage display' do
  let(:source) { File.read(File.expand_path('../../../../monadic.sh', __dir__)) }
  let(:functions) do
    %w[format_docker_disk_usage check_docker_disk_space].map do |name|
      definition = source[/^#{name}\(\) \{\n.*?^\}/m]
      raise "Missing function: #{name}" unless definition

      definition
    end.join("\n")
  end
  let(:rows) do
    [
      ['Images', '12', '4', '8.5GB', '3.2GB (37%)'],
      ['Containers', '5', '3', '24MB', '12MB (50%)'],
      ['Local Volumes', '8', '5', '1.2GB', '400MB (33%)'],
      ['Build Cache', '42', '0', '2.1GB', '2.1GB']
    ]
  end
  let(:disk_data) { rows.map { |row| row.join("\t") }.join("\n") }

  def run_bash(body, *args, input: '')
    out, err, status = Open3.capture3('bash', '-c', functions + "\n" + body,
                                     '_', *args, stdin_data: input)
    expect(status.success?).to be(true), err
    expect(err).to be_empty
    out
  end

  def table_rows(output)
    output.scan(/<tr\b[^>]*>(.*?)<\/tr>/).map do |row|
      row.first.scan(/<td\b[^>]*>(.*?)<\/td>/).flatten
    end
  end

  it 'preserves all five columns, multiword types, and reclaimable percentages' do
    output = run_bash('format_docker_disk_usage "$1"', disk_data)

    expect(output.lines.size).to eq(1)
    expect(output).to start_with('[HTML]: <table')
    expect(table_rows(output)).to eq([%w[TYPE TOTAL ACTIVE SIZE RECLAIMABLE]] + rows)
  end

  it 'ignores blank lines without adding empty table rows' do
    output = run_bash('format_docker_disk_usage "$1"', "\n#{disk_data}\n\n")

    expect(table_rows(output).drop(1)).to eq(rows)
  end

  it 'requests tab-separated Docker data and emits the complete table' do
    output = run_bash(<<~'BASH', input: disk_data)
      fake_docker() {
        [ "$#" -eq 4 ] && [ "$1" = system ] && [ "$2" = df ] &&
          [ "$3" = --format ] &&
          [ "$4" = '{{.Type}}\t{{.TotalCount}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}' ] || return 1
        cat
      }
      DOCKER=fake_docker
      check_docker_disk_space
    BASH

    expect(output).to include('Checking Docker disk usage...')
    expect(table_rows(output)).to eq([%w[TYPE TOTAL ACTIVE SIZE RECLAIMABLE]] + rows)
  end

  it 'continues without a table when Docker rejects --format, even with partial output' do
    output = run_bash(<<~'BASH')
      fake_docker() {
        printf 'partial output\n'
        printf 'unknown flag: --format\n' >&2
        return 1
      }
      DOCKER=fake_docker
      check_docker_disk_space
    BASH

    expect(output).to include('Unable to check Docker disk usage. Proceeding with build...')
    expect(output).not_to include('<table', 'partial output', 'unknown flag')
  end

  it 'continues without a table when Docker returns no data' do
    output = run_bash(<<~'BASH')
      fake_docker() { return 0; }
      DOCKER=fake_docker
      check_docker_disk_space
    BASH

    expect(output).to include('Unable to check Docker disk usage. Proceeding with build...')
    expect(output).not_to include('<table')
  end
end
