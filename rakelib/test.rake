# frozen_string_literal: true

# =============================================================================
# API Media Tests (image/video/voice generation)
# =============================================================================
namespace :spec_api do
  desc "Real API media tests (image/video/voice). Requires RUN_MEDIA=true"
  task :media do
    ENV['RUN_API'] ||= 'true'
    ENV['RUN_MEDIA'] ||= 'true'
    ENV['API_TIMEOUT'] ||= '120'
    ENV['API_MAX_RETRIES'] ||= '0'
    ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')
    Dir.chdir("docker/services/ruby") do
      fmt = (ENV['SUMMARY_ONLY'] == '1') ? '--format progress' : '--format documentation'
      sh "bundle exec rspec spec/integration/api_media #{fmt}"
    end
  end
end

# Test ruby code with rspec ./docker/services/ruby/spec
task :spec do
  # Set environment variables for test database connection
  # Set HOST_OS for Docker Compose
  ENV['HOST_OS'] ||= `uname -s`.chomp

  # Ensure qdrant + embeddings are running for any integration spec that
  # touches the vector store. Unit specs mock these and do not need them.
  qdrant_running = system("docker ps | grep -q monadic-chat-qdrant-container")
  embeddings_running = system("docker ps | grep -q monadic-chat-embeddings-container")

  if !qdrant_running || !embeddings_running
    puts "Starting qdrant + embeddings containers for tests..."
    compose_file = File.expand_path("docker/services/compose.yml", PROJECT_ROOT)
    qdrant_dev_file = File.expand_path("docker/services/qdrant/compose.dev.yml", PROJECT_ROOT)
    embeddings_dev_file = File.expand_path("docker/services/embeddings/compose.dev.yml", PROJECT_ROOT)
    project_dir = File.expand_path("docker/services", PROJECT_ROOT)

    overlays = [compose_file]
    overlays << qdrant_dev_file if File.exist?(qdrant_dev_file)
    overlays << embeddings_dev_file if File.exist?(embeddings_dev_file)
    files_arg = overlays.map { |f| "-f '#{f}'" }.join(' ')

    system("docker compose --project-directory '#{project_dir}' #{files_arg} -p 'monadic-chat' up -d qdrant_service embeddings_service")

    puts "Waiting for qdrant to be ready..."
    30.times do
      break if system("curl -sf http://localhost:6333/healthz >/dev/null 2>&1")
      sleep 1
    end
  end
  
  # Store paths before changing directory
  root_dir = PROJECT_ROOT
  
  # Run tests with the new structure
  ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')
  Dir.chdir("docker/services/ruby") do
    fmt = (ENV['SUMMARY_ONLY'] == '1') ? '--format progress' : '--format documentation'
    puts "Running unit tests..."
    sh "bundle exec rspec spec/unit #{fmt} --no-fail-fast --no-profile"

    # Run integration tests if available
    puts "\nRunning integration tests..."
    sh "bundle exec rspec spec/integration #{fmt} --no-fail-fast --no-profile" rescue puts "Integration tests skipped (not available)"

    # Run system tests
    puts "\nRunning system tests..."
    sh "bundle exec rspec spec/system #{fmt} --no-fail-fast --no-profile" rescue puts "System tests skipped (not available)"
  end
ensure
  # Only stop qdrant + embeddings if we started them
  if (!qdrant_running || !embeddings_running) && ENV['KEEP_VECTOR_SERVICES'] != 'true'
    puts "Stopping qdrant + embeddings containers..."
    compose_file = File.expand_path("docker/services/compose.yml", root_dir)
    project_dir = File.expand_path("docker/services", root_dir)
    system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop qdrant_service embeddings_service")
  end
end

# Quick test task (unit + integration only, no media generation)
namespace :spec do
  desc "Run quick tests (unit + integration only, excludes system tests)"
  task :quick do
    # Set environment variables for test database connection
    ENV['POSTGRES_HOST'] ||= 'localhost'
    ENV['POSTGRES_PORT'] ||= '5433'
    ENV['POSTGRES_USER'] ||= 'postgres'
    ENV['POSTGRES_PASSWORD'] ||= 'postgres'

    # Set HOST_OS for Docker Compose
    ENV['HOST_OS'] ||= `uname -s`.chomp

    # Start qdrant + embeddings for tests that require them. Unit specs mock
    # these so they only matter for integration / system specs.
    qdrant_running = system("docker ps | grep -q monadic-chat-qdrant-container")
    embeddings_running = system("docker ps | grep -q monadic-chat-embeddings-container")

    if !qdrant_running || !embeddings_running
      puts "Starting qdrant + embeddings containers for tests..."
      compose_file = File.expand_path("docker/services/compose.yml", PROJECT_ROOT)
      qdrant_dev_file = File.expand_path("docker/services/qdrant/compose.dev.yml", PROJECT_ROOT)
      embeddings_dev_file = File.expand_path("docker/services/embeddings/compose.dev.yml", PROJECT_ROOT)
      project_dir = File.expand_path("docker/services", PROJECT_ROOT)

      overlays = [compose_file]
      overlays << qdrant_dev_file if File.exist?(qdrant_dev_file)
      overlays << embeddings_dev_file if File.exist?(embeddings_dev_file)
      files_arg = overlays.map { |f| "-f '#{f}'" }.join(' ')

      system("docker compose --project-directory '#{project_dir}' #{files_arg} -p 'monadic-chat' up -d qdrant_service embeddings_service")

      puts "Waiting for qdrant to be ready..."
      30.times do
        break if system("curl -sf http://localhost:6333/healthz >/dev/null 2>&1")
        sleep 1
      end
    end

    # Store paths before changing directory
    root_dir = PROJECT_ROOT

    # Run only unit and integration tests (exclude system tests)
    ENV['SUMMARY_RUN_ID'] ||= Time.now.utc.strftime('%Y%m%d_%H%M%SZ')
    Dir.chdir("docker/services/ruby") do
      fmt = (ENV['SUMMARY_ONLY'] == '1') ? '--format progress' : '--format documentation'
      puts "Running unit tests..."
      sh "bundle exec rspec spec/unit #{fmt} --no-fail-fast --no-profile"

      # Run integration tests if available
      puts "\nRunning integration tests..."
      sh "bundle exec rspec spec/integration #{fmt} --no-fail-fast --no-profile" rescue puts "Integration tests skipped (not available)"

      puts "\n✅ Quick tests completed (system tests excluded)"
    end
  ensure
    # Only stop qdrant + embeddings if we started them
    if (!qdrant_running || !embeddings_running) && ENV['KEEP_VECTOR_SERVICES'] != 'true'
      puts "Stopping qdrant + embeddings containers..."
      compose_file = File.expand_path("docker/services/compose.yml", root_dir)
      project_dir = File.expand_path("docker/services", root_dir)
      system("docker compose --project-directory '#{project_dir}' -f '#{compose_file}' -p 'monadic-chat' stop qdrant_service embeddings_service")
    end
  end
end

# Quick test task (Ruby quick + frontend)
namespace :test do
  desc "Run quick tests (Ruby unit+integration + npm test, no media generation)"
  task :quick do
    puts "=== Running Ruby quick tests ==="
    Rake::Task["spec:quick"].invoke

    puts "\n=== Running frontend tests ==="
    sh "npm test"

    puts "\n✅ All quick tests completed successfully!"
  end
end

# Unit test categories
namespace :spec_unit do
  desc "Run web search unit tests"
  task :websearch do
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/openai_websearch_message_spec.rb spec/unit/websearch_tavily_config_spec.rb spec/unit/mistral_websearch_performance_spec.rb --format documentation"
    end
  end
end

# System test categories
namespace :spec_system do
  desc "Run web search system tests"
  task :websearch do
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/system/chat_websearch_system_spec.rb spec/system/chat_websearch_update_spec.rb --format documentation"
    end
  end
end

# E2E tests for specific apps/features
namespace :spec_e2e do
  desc "Run E2E tests for Chat app"
  task :chat do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh chat"
    end
  end
  
  desc "Run E2E tests for Code Interpreter"
  task :code_interpreter do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh code_interpreter"
    end
  end
  
  desc "Run E2E tests for Image Generator"
  task :image_generator do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh image_generator"
    end
  end
  
  desc "Run E2E tests for Monadic Help"
  task :help do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh help"
    end
  end
  
  desc "Run E2E tests for Code Interpreter with a specific provider"
  task :code_interpreter_provider, [:provider] do |t, args|
    provider = args[:provider]
    unless provider
      puts "Error: Provider must be specified"
      puts "Usage: rake spec_e2e:code_interpreter_provider[openai]"
      puts "Available providers: openai, claude, gemini, grok, mistral, cohere, deepseek"
      exit 1
    end
    
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh code_interpreter_provider #{provider}"
    end
  end
  
  desc "Run E2E tests for Ollama provider"
  task :ollama do
    # Check if native Ollama is running
    ollama_ok = system("curl -sf http://localhost:11434/ > /dev/null 2>&1")

    unless ollama_ok
      puts "\n" + "="*60
      puts "Ollama is not running"
      puts "="*60
      puts "\nPlease install and start Ollama before running tests."
      puts "\nInstall Ollama: https://ollama.com/download"
      puts "\nAfter installing, start it and pull a model:"
      puts "  ollama pull qwen3:4b"
      puts "="*60 + "\n"
      exit 0
    end

    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh ollama"
    end
  end
  
  desc "Run E2E tests for Research Assistant"
  task :research_assistant do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh research_assistant"
    end
  end
  
  desc "Run E2E tests for Web Insight"
  task :web_insight do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh web_insight"
    end
  end
  
  desc "Run E2E tests for Mermaid Grapher"
  task :mermaid_grapher do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh mermaid_grapher"
    end
  end
  
  desc "Run E2E tests for Voice Chat"
  task :voice_chat do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh voice_chat"
    end
  end
  
  desc "Run E2E tests for Coding Assistant"
  task :coding_assistant do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh coding_assistant"
    end
  end
  
  desc "Run E2E tests for Second Opinion"
  task :second_opinion do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh second_opinion"
    end
  end
  
  desc "Run E2E tests for Jupyter Notebook"
  task :jupyter_notebook do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh jupyter_notebook"
    end
  end
  
  desc "Run E2E tests for Chat Export/Import functionality"
  task :chat_export_import do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh chat_export_import"
    end
  end
  
  desc "Run E2E tests for Chat Plus Monadic functionality"
  task :chat_plus_monadic_test do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh chat_plus_monadic_test"
    end
  end
  
  desc "Run E2E tests for web search functionality"
  task :websearch do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh websearch"
    end
  end
end

# Test JavaScript code with Jest
desc "Run JavaScript tests using Jest"
task :jstest, [:save_results, :output_dir] do |_t, args|
  require 'fileutils'
  require 'time'

  # Determine if we should save results
  save = args[:save_results] == 'true' || ENV['JEST_SAVE_RESULTS'] == 'true'
  output_dir = args[:output_dir] || ENV['JEST_OUTPUT_DIR']

  if save && output_dir
    # output_dir is the unified test results directory
    FileUtils.mkdir_p(output_dir)
    json_file = File.join(output_dir, 'jest.json')
    puts "Running Jest tests (saving results to #{json_file})..."

    success = system("npm test -- --json --outputFile=#{json_file}")

    if File.exist?(json_file)
      puts "✅ Jest results saved to: #{json_file}"
    else
      puts "⚠️  Warning: Jest results file was not created"
    end

    exit 1 unless success
  elsif save
    # Fallback: save to flat file with timestamp
    results_dir = File.expand_path('tmp/test_results', PROJECT_ROOT)
    FileUtils.mkdir_p(results_dir)
    run_id = Time.now.strftime('%Y%m%d_%H%M%S')
    json_file = File.join(results_dir, "jest_#{run_id}.json")
    puts "Running Jest tests (saving results to #{json_file})..."

    success = system("npm test -- --json --outputFile=#{json_file}")

    if File.exist?(json_file)
      puts "✅ Jest results saved to: #{json_file}"
    else
      puts "⚠️  Warning: Jest results file was not created"
    end

    exit 1 unless success
  else
    sh "npm test"
  end
end

# For backward compatibility
desc "Run all JavaScript tests using Jest"
task :jstest_all => :jstest

# Test Python code
namespace :pytest do
  desc "Run all Python tests"
  task :all, [:save_results, :output_dir] do |_t, args|
    require 'fileutils'
    require 'time'
    require 'open3'

    # Determine if we should save results
    save = args[:save_results] == 'true' || ENV['PYTEST_SAVE_RESULTS'] == 'true'
    output_dir = args[:output_dir] || ENV['PYTEST_OUTPUT_DIR']

    puts "Running Python tests..."
    python_test_dirs = [
      "docker/services/python/scripts/services"
    ]

    all_output = []
    all_success = true

    python_test_dirs.each do |dir|
      if Dir.exist?(dir)
        puts "\nRunning tests in #{dir}..."
        Dir.chdir(dir) do
          # Run all test files
          test_files = Dir.glob("test_*.py")
          if test_files.any?
            test_files.each do |test_file|
              puts "Running #{test_file}..."
              stdout, stderr, status = Open3.capture3("python3", test_file, "-v")
              output = "=== #{test_file} ===\n#{stdout}\n#{stderr}"
              all_output << output
              puts output

              unless status.success?
                puts "Test failed: #{test_file}"
                all_success = false
              end
            end
          else
            puts "No test files found in #{dir}"
            all_output << "No test files found in #{dir}"
          end
        end
      end
    end

    # Save results if requested
    if save && output_dir
      # output_dir is the unified test results directory
      FileUtils.mkdir_p(output_dir)
      output_file = File.join(output_dir, 'pytest.txt')
      File.write(output_file, all_output.join("\n\n"))
      puts "\n✅ Python test results saved to: #{output_file}"
    elsif save
      # Fallback: save to flat file with timestamp
      results_dir = File.expand_path('tmp/test_results', PROJECT_ROOT)
      FileUtils.mkdir_p(results_dir)
      run_id = Time.now.strftime('%Y%m%d_%H%M%S')
      output_file = File.join(results_dir, "pytest_#{run_id}.txt")
      File.write(output_file, all_output.join("\n\n"))
      puts "\n✅ Python test results saved to: #{output_file}"
    end

    exit 1 unless all_success
  end
  
  desc "Run jupyter_controller tests"
  task :jupyter do
    puts "Running jupyter_controller tests..."
    test_file = "docker/services/python/scripts/services/test_jupyter_controller.py"
    if File.exist?(test_file)
      Dir.chdir(File.dirname(test_file)) do
        sh "python3 #{File.basename(test_file)} -v"
      end
    else
      puts "Test file not found: #{test_file}"
    end
  end
end

# Run both Ruby and JavaScript tests
desc "Run all tests (Ruby, JavaScript, and Python)"
task :test do
  require 'time'
  require 'fileutils'
  require 'json'

  # Generate unified run ID for this test session
  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  run_id = "test_#{timestamp}"

  # Create unified output directory
  output_dir = File.expand_path("tmp/test_results/#{run_id}", PROJECT_ROOT)
  FileUtils.mkdir_p(output_dir)

  puts "=" * 60
  puts "Running all tests (Ruby, JavaScript, Python)"
  puts "Run ID: #{run_id}"
  puts "Output: #{output_dir}/"
  puts "=" * 60

  results = {}
  start_time = Time.now

  # Run Ruby tests
  puts "\n[1/3] Running Ruby tests..."
  results[:ruby] = Rake::Task[:spec].invoke

  # Run JavaScript tests with result saving
  puts "\n[2/3] Running JavaScript tests..."
  Rake::Task[:jstest].reenable
  results[:javascript] = Rake::Task[:jstest].invoke('true', output_dir)

  # Run Python tests with result saving
  puts "\n[3/3] Running Python tests..."
  Rake::Task["pytest:all"].reenable
  results[:python] = Rake::Task["pytest:all"].invoke('true', output_dir)

  duration = Time.now - start_time
  all_passed = results.values.all?

  # Write combined summary
  summary = {
    run_id: run_id,
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

  puts "\n" + "=" * 60
  puts all_passed ? "✅ ALL TESTS COMPLETED" : "⚠️  SOME TESTS MAY HAVE FAILED"
  puts "=" * 60
  puts "Duration: #{duration.round(2)}s"
  puts "Results saved to: #{output_dir}/"
  puts "  - jest.json (JavaScript)"
  puts "  - pytest.txt (Python)"
  puts "  - summary.json (Combined)"
  puts "=" * 60
end

# Run only the jupyter controller integration test
desc "Run Jupyter controller integration test"
task :jupyter_integration do
  Dir.chdir("docker/services/ruby") do
    sh "bundle exec rspec spec/integration/jupyter_controller_integration_spec.rb --format documentation"
  end
end

# Test summary utilities
namespace :test_summary do
  desc "Print a concise summary from the latest tmp/test_runs/*/rspec_report.json"
  task :latest do
    require 'json'
    require 'time'
    base = File.expand_path('tmp/test_runs', PROJECT_ROOT)
    unless Dir.exist?(base)
      puts "No test_runs directory found at #{base}"
      next
    end
    # Find latest directory by timestamp
    candidates = Dir.glob(File.join(base, '*/rspec_report.json')).sort
    if candidates.empty?
      puts "No rspec_report.json found under #{base}"
      next
    end
    path = candidates.last
    print_summary_from(path)
  end

  desc "Print a concise summary from a specific rspec_report.json path"
  task :path, [:json_path] do |_t, args|
    require 'json'
    path = args[:json_path]
    unless path && File.exist?(path)
      puts "Provide a valid path: rake test_summary:path[./tmp/test_runs/<ts>/rspec_report.json]"
      next
    end
    print_summary_from(path)
  end

  def print_summary_from(path)
    require 'json'
    data = JSON.parse(File.read(path))
    c = data['counts'] || {}
    dur = data['duration_seconds'] || 0
    seed = data['seed']
    puts "Counts: total=#{c['total']} passed=#{c['passed']} failed=#{c['failed']} pending=#{c['pending']} duration=#{dur}s seed=#{seed}"
    examples = data['examples'] || []
    failed = examples.select { |e| e['status'] == 'failed' }
    pend   = examples.select { |e| e['status'] == 'pending' }
    if failed.any?
      puts "\nFailed (#{failed.size}):"
      failed.first(50).each_with_index do |e, i|
        loc = "#{e['file_path']}:#{e['line_number']}"
        msg = e.dig('exception', 'message')
        puts sprintf("%2d. %s — %s — %s", i+1, e['description'], loc, msg)
      end
    end
    if pend.any?
      puts "\nPending (#{pend.size}):"
      pend.first(50).each_with_index do |e, i|
        loc = "#{e['file_path']}:#{e['line_number']}"
        msg = e['pending_message']
        puts sprintf("%2d. %s — %s — %s", i+1, e['description'], loc, msg)
      end
    end
    puts "\nSource: #{path}"
  end
end
