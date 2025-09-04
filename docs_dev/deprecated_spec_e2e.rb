# Deprecated spec_e2e namespace tasks
# These have been replaced by apps:test_* tasks
# Preserved here for reference - can be deleted after migration period

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
  
  desc "Run E2E tests for PDF Navigator"
  task :pdf_navigator do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh pdf_navigator"
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
    # Check if Ollama container exists
    ollama_exists = `docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^yohasebe/ollama:" 2>/dev/null`.strip
    
    if ollama_exists.empty?
      puts "\n" + "="*60
      puts "Ollama container not found"
      puts "="*60
      puts "\nThe Ollama container needs to be built before running tests."
      puts "\nTo build the Ollama container:"
      puts "  1. In the UI: Actions → Build Ollama Container"
      puts "  2. Or run: ./docker/monadic.sh build_ollama_container"
      puts "\nNote: Building will download the default model (llama3.2)"
      puts "      which may take some time depending on your connection."
      puts "="*60 + "\n"
      exit 0
    end
    
    # Check if Ollama container is running
    ollama_running = `docker ps --format "{{.Names}}" | grep -E "^monadic-chat-ollama-container$" 2>/dev/null`.strip
    
    if ollama_running.empty?
      puts "\nStarting Ollama container..."
      system("docker start monadic-chat-ollama-container")
      
      # Wait a moment for the container to start
      sleep 2
      
      # Verify it started
      ollama_running = `docker ps --format "{{.Names}}" | grep -E "^monadic-chat-ollama-container$" 2>/dev/null`.strip
      if ollama_running.empty?
        puts "\nFailed to start Ollama container. Please check Docker logs."
        exit 1
      end
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
  
  desc "Run E2E tests for Visual Web Explorer"
  task :visual_web_explorer do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh visual_web_explorer"
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
  
  desc "Run E2E tests for Content Reader"
  task :content_reader do
    Dir.chdir("docker/services/ruby") do
      sh "./spec/e2e/run_e2e_tests.sh content_reader"
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