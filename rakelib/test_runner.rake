# frozen_string_literal: true

# -----------------------------------------------------------------------------
# Unified Test Runner tasks (developer UX)
# -----------------------------------------------------------------------------
namespace :test do
  desc "Show available test suites and options"
  task :help do
    require_relative '../lib/test_runner'
    TestRunner.show_help
  end

  desc "Run tests with user-friendly interface"
  task :run, [:suite, :options] do |_t, args|
    require_relative '../lib/test_runner'
    runner = TestRunner.new(args[:suite], args[:options])
    runner.execute
  end

  desc "Run tests using predefined profile from config/test/test-config.yml (fallback: .test-config.yml)"
  task :profile, [:name] do |_t, args|
    require 'yaml'
    require_relative '../lib/test_runner'
    # Prefer new path, fall back to legacy path for backward compatibility
    config_path = ENV['TEST_PROFILE_PATH'] || 'config/test/test-config.yml'
    unless File.exist?(config_path)
      legacy = '.test-config.yml'
      if File.exist?(legacy)
        config_path = legacy
        puts "[test:profile] Using legacy profile path: #{legacy}"
      else
        puts "Profile config not found: #{config_path} (or #{legacy})"
        exit 1
      end
    end
    cfg = YAML.safe_load(File.read(config_path)) || {}
    profiles = cfg['profiles'] || {}
    profile = profiles[args[:name]]
    if profile.nil?
      puts "Profile '#{args[:name]}' not found"
      puts "Available profiles: #{profiles.keys.join(', ')}"
      exit 1
    end
    suites = profile['suites'] || []
    common_opts = profile.reject { |k, _| k == 'suites' }
    suites.each do |suite|
      options_str = common_opts.map { |k, v| "#{k}=#{Array(v).join(',')}" }.join(',')
      Rake::Task['test:run'].invoke(suite, options_str)
      Rake::Task['test:run'].reenable
    end
  end

  desc "List recent test results"
  task :history, [:count] do |_t, args|
    require_relative '../lib/test_runner'
    TestRunner.show_history((args[:count] || 10).to_i)
  end

  desc "Compare two test runs (by run_id)"
  task :compare, [:run1, :run2] do |_t, args|
    require_relative '../lib/test_runner'
    TestRunner.compare_runs(args[:run1], args[:run2])
  end

  desc "Clean up old test results (keep latest N, default: 3)"
  task :cleanup, [:keep_count] do |_t, args|
    require 'fileutils'

    keep_count = (args[:keep_count] || ENV['TEST_KEEP_COUNT'] || '3').to_i
    results_dir = File.expand_path('tmp/test_results', PROJECT_ROOT)

    unless Dir.exist?(results_dir)
      puts "No test results directory found at #{results_dir}"
      next
    end

    # Get all timestamped directories (YYYYMMDD_HHMMSS format)
    dirs = Dir.glob(File.join(results_dir, '2*')).select { |f| File.directory?(f) }

    # Sort by modification time (newest first)
    sorted_dirs = dirs.sort_by { |d| File.mtime(d) }.reverse

    # Get directories and files to delete
    to_delete_dirs = sorted_dirs[keep_count..-1] || []

    # Also clean up orphaned files (jest.json, pytest.txt, etc.)
    all_files = Dir.glob(File.join(results_dir, '*')).select { |f| File.file?(f) }

    # Keep files associated with kept directories and summary files
    kept_run_ids = sorted_dirs[0...keep_count].map { |d| File.basename(d) }
    to_delete_files = all_files.reject do |f|
      basename = File.basename(f)
      # Keep latest symlink, summary files, and files matching kept run IDs
      basename == 'latest' ||
      basename.start_with?('summary_') ||
      basename.start_with?('index_') ||
      kept_run_ids.any? { |id| basename.include?(id) }
    end

    if to_delete_dirs.empty? && to_delete_files.empty?
      puts "No old test results to clean up (keeping latest #{keep_count})"
      next
    end

    puts "Cleaning up old test results (keeping latest #{keep_count})..."

    deleted_count = 0
    to_delete_dirs.each do |dir|
      puts "  Deleting: #{File.basename(dir)}/"
      FileUtils.rm_rf(dir)
      deleted_count += 1
    end

    to_delete_files.each do |file|
      puts "  Deleting: #{File.basename(file)}"
      FileUtils.rm_f(file)
      deleted_count += 1
    end

    puts "✅ Cleaned up #{deleted_count} items"
    puts "Kept #{sorted_dirs.size - to_delete_dirs.size} recent test results"
  end

  desc "Run all tests (Ruby, JavaScript, Python) with unified runner"
  task :all, [:api_level, :open] do |_t, args|
    require_relative '../lib/test_runner'
    require 'json'
    require 'fileutils'

    api_level = args[:api_level] || ENV['TEST_API_LEVEL'] || 'standard'
    want_open = (args[:open].to_s == 'true' || ENV['OPEN_INDEX'] == 'true')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    run_id = timestamp

    # Create unified output directory for all test results
    output_dir = File.expand_path("tmp/test_results/#{run_id}", PROJECT_ROOT)
    FileUtils.mkdir_p(output_dir)

    # Set TEST_OUTPUT_DIR so RSpec SummaryFormatter uses this directory
    ENV['TEST_OUTPUT_DIR'] = output_dir

    # Pre-check: Docker daemon must be running for Ruby tests
    docker_check = system("docker info > /dev/null 2>&1")
    unless docker_check
      puts "\n❌ Docker daemon is not running!"
      puts "   Please start Docker Desktop before running tests."
      puts "   (JavaScript and Python tests do not require Docker)\n\n"
      exit 1
    end

    # Determine what tests to run based on api_level
    run_media = (api_level == 'full')
    run_websearch = (api_level == 'full')

    # Set environment variables for test runs
    if api_level == 'full'
      ENV['RUN_MEDIA'] = 'true'
      ENV['RUN_WEBSEARCH_TESTS'] = 'true'
      ENV['RUN_API'] = 'true'
    elsif api_level == 'standard'
      ENV['RUN_API'] = 'true'
    end

    # Calculate total steps
    total_steps = 5  # unit, integration, system, javascript, python
    total_steps += 1 if api_level != 'none'  # api tests
    total_steps += 1 if run_media             # media tests
    total_steps += 1 if run_websearch         # websearch tests

    # Build banner with proper display-width alignment
    banner_width = 42  # Inner width between ║ characters
    puts "╔#{'═' * banner_width}╗"
    puts "║#{DisplayWidthHelpers.center('Monadic Chat - Full Test Suite', banner_width)}║"
    puts "║   API Level: #{DisplayWidthHelpers.ljust(api_level, banner_width - 14)}║"
    puts "║   Media Tests: #{DisplayWidthHelpers.ljust(run_media ? 'enabled' : 'disabled', banner_width - 16)}║"
    puts "║   Websearch Tests: #{DisplayWidthHelpers.ljust(run_websearch ? 'enabled' : 'disabled', banner_width - 20)}║"
    puts "║   Output: #{DisplayWidthHelpers.ljust(run_id, banner_width - 11)}║"
    puts "╚#{'═' * banner_width}╝"

    results = {}
    start_time = Time.now
    step = 0

    # Ruby unit tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Ruby unit tests..."
    unit_json = File.join(output_dir, 'unit.json')
    Dir.chdir("docker/services/ruby") do
      results[:ruby_unit] = system("bundle exec rspec spec/unit --format documentation --format json --out #{unit_json}")
    end

    # Ruby integration tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Ruby integration tests..."
    integration_json = File.join(output_dir, 'integration.json')
    Dir.chdir("docker/services/ruby") do
      results[:ruby_integration] = system("bundle exec rspec spec/integration --format documentation --format json --out #{integration_json}")
    end

    # Ruby system tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Ruby system tests..."
    system_json = File.join(output_dir, 'system.json')
    Dir.chdir("docker/services/ruby") do
      results[:ruby_system] = system("bundle exec rspec spec/system --format documentation --format json --out #{system_json}")
    end

    # API tests (optional by level)
    if api_level != 'none'
      step += 1
      puts "\n🧪 [#{step}/#{total_steps}] Running API tests..."
      api_json = File.join(output_dir, 'api.json')
      Dir.chdir("docker/services/ruby") do
        results[:api] = system("bundle exec rspec spec/integration --tag api --format documentation --format json --out #{api_json}")
      end
    else
      results[:api] = true
    end

    # Media tests (only on 'full' API level)
    if run_media
      step += 1
      puts "\n🧪 [#{step}/#{total_steps}] Running Media tests (image/video/audio generation)..."
      media_json = File.join(output_dir, 'media.json')
      Dir.chdir("docker/services/ruby") do
        results[:media] = system("bundle exec rspec spec/integration/api_media --format documentation --format json --out #{media_json}")
      end
    else
      results[:media] = true
    end

    # Websearch API tests (only on 'full' API level)
    if run_websearch
      step += 1
      puts "\n🧪 [#{step}/#{total_steps}] Running Websearch API tests..."
      websearch_json = File.join(output_dir, 'websearch.json')
      Dir.chdir("docker/services/ruby") do
        # Run websearch-tagged integration tests
        results[:websearch] = system("bundle exec rspec spec/integration --tag websearch --format documentation --format json --out #{websearch_json}")
      end
    else
      results[:websearch] = true
    end

    # JavaScript tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running JavaScript tests..."
    # Use system() to run as subprocess - invoke() returns task object, not result
    results[:javascript] = system("rake 'jstest[true,#{output_dir}]'")

    # Python tests
    step += 1
    puts "\n🧪 [#{step}/#{total_steps}] Running Python tests..."
    # Use system() to run as subprocess - invoke() returns task object, not result
    results[:python] = system("rake 'pytest:all[true,#{output_dir}]'")

    duration = Time.now - start_time
    all_passed = results.values.all?

    # Write combined summary
    summary = {
      run_id: run_id,
      api_level: api_level,
      timestamp: timestamp,
      duration: duration.round(2),
      results: results,
      overall_status: all_passed ? 'passed' : 'failed'
    }
    File.write(File.join(output_dir, 'summary.json'), JSON.pretty_generate(summary))

    # Create symlink to latest
    latest_link = File.expand_path('tmp/test_results/latest', PROJECT_ROOT)
    FileUtils.rm_f(latest_link)
    FileUtils.ln_sf(output_dir, latest_link)

    # Generate a simple index HTML bundling suite reports
    begin
      require_relative '../lib/test_index_html'
      suites = []
      suites << { name: :unit,        file: 'unit.json',        status: results[:ruby_unit] }
      suites << { name: :integration, file: 'integration.json', status: results[:ruby_integration] }
      suites << { name: :system,      file: 'system.json',      status: results[:ruby_system] }
      suites << { name: :api,         file: 'api.json',         status: results[:api] } if api_level != 'none'
      suites << { name: :media,       file: 'media.json',       status: results[:media] } if run_media
      suites << { name: :websearch,   file: 'websearch.json',   status: results[:websearch] } if run_websearch
      suites << { name: :javascript,  file: 'jest.json',        status: results[:javascript] }
      suites << { name: :python,      file: 'pytest.txt',       status: results[:python] }
      idx_path = File.join(output_dir, 'index.html')
      TestIndexHTML.generate_unified(output_dir, run_id, suites, idx_path)
      puts "\n📄 Index report generated: #{idx_path}"
      if want_open
        if RUBY_PLATFORM =~ /darwin/i
          system("open", idx_path)
        else
          puts "(Auto-open is only supported on macOS; skipping)"
        end
      end
    rescue StandardError => e
      puts "⚠️  Could not generate index HTML: #{e.message}"
    end

    puts "\n" + "=" * 50
    puts all_passed ? "✅ ALL TESTS PASSED!" : "❌ SOME TESTS FAILED"
    puts "=" * 50
    puts "Duration: #{duration.round(2)}s"
    puts "Results saved to: #{output_dir}/"

    if !all_passed
      failed = results.select { |_, v| !v }.keys
      puts "\nFailed components: #{failed.join(', ')}"
    end

    exit(all_passed ? 0 : 1)
  end

  desc "Run quick smoke tests (subset of all tests)"
  task :smoke, [:api_level] do |_t, args|
    api_level = args[:api_level] || 'none'
    puts "🚬 Running smoke tests (api_level=#{api_level})..."
    system("rake test:run[unit,\"api_level=#{api_level},focus=critical\"]")
  end

  desc "Run JavaScript tests via unified runner"
  task :js do
    require_relative '../lib/test_runner'
    TestRunner.new('js').execute
  end

  desc "Run Python tests via unified runner"
  task :python do
    require_relative '../lib/test_runner'
    TestRunner.new('python').execute
  end

  desc "Analyze last test run results and extract failures/pending"
  task :analyze, [:run_id] do |_t, args|
    require 'json'
    require_relative '../lib/test_result_analyzer'
    run_id = args[:run_id]
    if run_id.nil?
      latest = Dir.glob('tmp/test_results/*_meta.json').max_by { |f| File.mtime(f) }
      run_id = latest && File.basename(latest).sub(/_meta\.json\z/, '')
    end
    if run_id.nil?
      puts 'No test results found'
      next
    end
    json_path = File.join('tmp', 'test_results', "#{run_id}.json")
    TestResultAnalyzer.analyze_and_save(json_path, run_id)
    puts "Analysis complete for #{run_id}"
  end

  desc "Generate HTML report for a test run (default: latest)"
  task :report, [:run_id, :out] do |_t, args|
    require 'fileutils'
    require_relative '../lib/test_report_html'
    results_dir = File.join('tmp', 'test_results')
    FileUtils.mkdir_p(results_dir)
    run_id = args[:run_id]
    if run_id.nil?
      latest = Dir.glob(File.join(results_dir, '*_meta.json')).max_by { |f| File.mtime(f) }
      run_id = latest && File.basename(latest).sub(/_meta\.json\z/, '')
    end
    if run_id.nil?
      puts 'No test results found'
      next
    end
    out = args[:out] || File.join(results_dir, "report_#{run_id}.html")
    path = TestReportHTML.generate(results_dir, run_id, out)
    puts "HTML report generated: #{path}"
  end
end
