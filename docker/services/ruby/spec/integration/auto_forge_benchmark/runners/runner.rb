#!/usr/bin/env ruby
# frozen_string_literal: true

# AutoForge Benchmark Runner
#
# Step 2a (this commit): Scaffold only. The runner can parse tasks and
# configs, validate the spec, and produce empty result directories. The
# actual LLM call orchestration is left as TODO for Step 2b.
#
# Step 2b: Wire up to AutoForgeClaude (or a programmatic equivalent) and
# execute task × config combinations against the live Anthropic API.
#
# Usage:
#   bundle exec ruby runner.rb                              # Full matrix
#   bundle exec ruby runner.rb --task easy_calculator       # One task
#   bundle exec ruby runner.rb --config A                   # One config
#   bundle exec ruby runner.rb --dry-run                    # Validate, no LLM calls

require 'optparse'
require 'yaml'
require 'json'
require 'time'
require 'fileutils'

# --- Config matrix ---------------------------------------------------------
# Edit CONFIGS to add or remove combinations.
# Each entry: { id, orchestrator_model, code_subagent_model, description }
CONFIGS = [
  {
    id: 'A',
    orchestrator_model: 'claude-sonnet-4-6',
    code_subagent_model: 'claude-sonnet-4-6',
    description: 'Baseline (current default)'
  },
  {
    id: 'B',
    orchestrator_model: 'claude-sonnet-4-6',
    code_subagent_model: 'claude-opus-4-7',
    description: 'Anti-inverted (orchestrator → stronger code agent)'
  },
  {
    id: 'C',
    orchestrator_model: 'claude-haiku-4-5-20251001',
    code_subagent_model: 'claude-sonnet-4-6',
    description: 'Cost-optimized (cheap orchestrator → mid-tier code)'
  }
].freeze

BENCHMARK_DIR = File.expand_path('..', __dir__)
TASKS_DIR     = File.join(BENCHMARK_DIR, 'tasks')
RESULTS_DIR   = File.join(BENCHMARK_DIR, 'results')

def parse_args
  opts = { task: nil, config: nil, dry_run: false }
  OptionParser.new do |p|
    p.banner = 'Usage: runner.rb [options]'
    p.on('--task TASK',     'Run only this task id')        { |v| opts[:task] = v }
    p.on('--config CONFIG', 'Run only this config id (A/B/C)') { |v| opts[:config] = v }
    p.on('--dry-run',       'Validate specs, do not call LLM') { opts[:dry_run] = true }
    p.on('-h', '--help')                                    { puts p; exit 0 }
  end.parse!
  opts
end

def load_tasks(filter_id = nil)
  files = Dir.glob(File.join(TASKS_DIR, '*.yml')).sort
  tasks = files.map { |f| YAML.load_file(f) }
  tasks.reject! { |t| t.nil? || t['id'].nil? }
  tasks.select! { |t| t['id'] == filter_id } if filter_id
  tasks
end

def select_configs(filter_id = nil)
  return CONFIGS unless filter_id
  CONFIGS.select { |c| c[:id] == filter_id }
end

def validate_task(task)
  errs = []
  %w[id difficulty description rubric_items smoke_test].each do |k|
    errs << "missing #{k}" if task[k].nil? || task[k].to_s.strip.empty?
  end
  if task['rubric_items'].is_a?(Array)
    task['rubric_items'].each_with_index do |item, i|
      errs << "rubric_items[#{i}] missing id" if item['id'].nil?
      errs << "rubric_items[#{i}] missing description" if item['description'].nil?
    end
  else
    errs << 'rubric_items must be an array'
  end
  errs
end

def run_one(task, config, dry_run:, run_dir:)
  task_dir = File.join(run_dir, "#{task['id']}-#{config[:id]}")
  FileUtils.mkdir_p(task_dir)

  if dry_run
    puts "  [DRY RUN] #{task['id']} × #{config[:id]} would run here"
    File.write(File.join(task_dir, 'dry_run.json'), JSON.pretty_generate(
      task_id: task['id'], config_id: config[:id], status: 'dry_run_only'
    ))
    return
  end

  # TODO (Step 2b): Implement the actual AutoForge execution loop.
  # Pseudocode:
  #
  #   project_state = AutoForge.start(
  #     description: task['description'],
  #     orchestrator: { model: config[:orchestrator_model] },
  #     code_subagent: { model: config[:code_subagent_model] },
  #     output_dir: File.join(task_dir, 'project')
  #   )
  #
  #   while !project_state.complete? && project_state.iterations < MAX_ITERATIONS
  #     project_state.advance
  #   end
  #
  #   output_file = project_state.main_output_path
  #
  #   functional_pass  = FunctionalScorer.new(task).score(output_file)
  #   rubric_coverage  = RubricScorer.new(task).score(output_file)
  #   code_quality     = QualityScorer.new(task).score(output_file)
  #
  #   File.write(File.join(task_dir, 'result.json'), JSON.pretty_generate(
  #     task_id: task['id'],
  #     config_id: config[:id],
  #     functional_pass: functional_pass,
  #     rubric_coverage: rubric_coverage,
  #     code_quality_score: code_quality,
  #     iteration_count: project_state.iterations,
  #     total_latency_sec: project_state.elapsed,
  #     input_tokens: project_state.input_tokens,
  #     output_tokens: project_state.output_tokens,
  #     estimated_cost_usd: estimate_cost(project_state, config)
  #   ))

  warn "  [TODO] #{task['id']} × #{config[:id]} — runner not yet wired (Step 2b)"
  File.write(File.join(task_dir, 'pending.json'), JSON.pretty_generate(
    task_id: task['id'],
    config_id: config[:id],
    status: 'pending_step_2b'
  ))
end

def main
  opts = parse_args
  tasks   = load_tasks(opts[:task])
  configs = select_configs(opts[:config])

  if tasks.empty?
    abort "No tasks matched (filter: #{opts[:task].inspect})"
  end
  if configs.empty?
    abort "No configs matched (filter: #{opts[:config].inspect})"
  end

  # Validation
  validation_errors = {}
  tasks.each do |t|
    errs = validate_task(t)
    validation_errors[t['id']] = errs unless errs.empty?
  end
  unless validation_errors.empty?
    warn 'Validation errors:'
    validation_errors.each { |id, errs| warn "  #{id}: #{errs.join(', ')}" }
    exit 1
  end

  puts "AutoForge Benchmark Runner"
  puts "  tasks:   #{tasks.map { |t| t['id'] }.join(', ')}"
  puts "  configs: #{configs.map { |c| c[:id] }.join(', ')}"
  puts "  dry-run: #{opts[:dry_run]}"
  puts

  timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  run_dir   = File.join(RESULTS_DIR, timestamp)
  FileUtils.mkdir_p(run_dir)

  tasks.each do |task|
    configs.each do |config|
      puts "Running: #{task['id']} × config #{config[:id]} (#{config[:description]})"
      run_one(task, config, dry_run: opts[:dry_run], run_dir: run_dir)
    end
  end

  summary_path = File.join(run_dir, 'summary.json')
  File.write(summary_path, JSON.pretty_generate(
    timestamp: timestamp,
    tasks: tasks.map { |t| t['id'] },
    configs: configs.map { |c| c[:id] },
    dry_run: opts[:dry_run],
    status: opts[:dry_run] ? 'dry_run' : 'pending_step_2b'
  ))
  puts
  puts "Results: #{run_dir}"
  puts "Summary: #{summary_path}"
end

main if __FILE__ == $PROGRAM_NAME
