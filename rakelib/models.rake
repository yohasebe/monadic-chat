# frozen_string_literal: true

# Model specification synchronization tasks
namespace :models do
  desc "Check model specification synchronization with provider APIs"
  task :check do
    puts "Checking model specification synchronization..."
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/model_spec_validation_spec.rb:297 --format documentation"
    end
  end
  
  desc "Run full model specification validation tests"
  task :validate do
    puts "Running full model specification validation tests..."
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/model_spec_validation_spec.rb --format documentation"
    end
  end
  
  desc "Generate a summary report of model synchronization status"
  task :report do
    puts "\n" + "=" * 80
    puts "MODEL SPECIFICATION SYNCHRONIZATION REPORT"
    puts "=" * 80
    puts "\nThis report shows which models need to be added or removed from model_spec.js"
    puts "to stay synchronized with each provider's API.\n\n"
    
    Dir.chdir("docker/services/ruby") do
      sh "bundle exec rspec spec/unit/model_spec_validation_spec.rb:297 --format progress 2>/dev/null | grep -E '(✓|⚠️|✅|Models in|Missing|deprecated)'"
    end
    
    puts "\n" + "=" * 80
    puts "To update model_spec.js, edit: docker/services/ruby/public/js/monadic/model_spec.js"
    puts "=" * 80
  end
  
  desc "Test custom models loading system"
  task :test_custom do
    puts "\n" + "=" * 80
    puts "CUSTOM MODELS SYSTEM TESTS"
    puts "=" * 80
    
    Dir.chdir("docker/services/ruby") do
      puts "\n📝 Running unit tests for ModelSpecLoader..."
      sh "bundle exec rspec spec/unit/model_spec_loader_spec.rb --format documentation"
      
      puts "\n📝 Running unit tests for API endpoint..."
      sh "bundle exec rspec spec/unit/api_models_endpoint_spec.rb --format documentation"
      
      puts "\n📝 Running integration tests..."
      sh "bundle exec rspec spec/integration/model_spec_loader_integration_spec.rb --format documentation"
    end
    
    puts "\n" + "=" * 80
    puts "✅ All custom models system tests completed!"
    puts "=" * 80
  end
  
  desc "Test all model-related functionality"
  task :test_all => [:validate, :test_custom] do
    puts "\n" + "=" * 80
    puts "✅ All model tests completed successfully!"
    puts "=" * 80
  end
end
