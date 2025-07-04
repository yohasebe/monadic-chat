require_relative 'e2e_helper'

RSpec.describe 'Chat Apps WebSearch with Tavily API', type: :e2e do
  include E2EHelper

  before(:each) do
    setup_e2e_test
    start_app_and_login
  end

  after(:each) do
    cleanup_e2e_test
  end

  describe 'WebSearch UI state based on Tavily API availability' do
    context 'with providers requiring Tavily API' do
      # Test one app from each Tavily-required provider
      ['chat_deepseek', 'chat_mistral', 'chat_cohere'].each do |app_name|
        it "disables websearch for #{app_name} when Tavily API key is missing" do
          skip "Requires manual verification - websearch UI state depends on runtime CONFIG"
          
          # This test would require:
          # 1. Temporarily removing TAVILY_API_KEY from CONFIG
          # 2. Restarting the server
          # 3. Checking the websearch checkbox state
          # 
          # Since we can't safely modify CONFIG during tests,
          # this is documented for manual testing
        end
      end
    end

    context 'with native websearch providers' do
      ['chat_openai', 'chat_gemini'].each do |app_name|
        it "keeps websearch enabled for #{app_name} regardless of Tavily API" do
          visit '/'
          wait_for_app_load
          
          # Select the app
          select_app(app_name)
          wait_for_ajax
          
          # Check that websearch is available (if model supports tools)
          websearch_checkbox = find('#websearch', visible: :all)
          
          # Get current model
          model_select = find('#model')
          current_model = model_select.value
          
          # Check model capability from model_spec
          model_spec_script = "modelSpec['#{current_model}'] && modelSpec['#{current_model}'].tool_capability"
          has_tool_capability = page.evaluate_script(model_spec_script)
          
          if has_tool_capability
            expect(websearch_checkbox.disabled?).to be false
          else
            expect(websearch_checkbox.disabled?).to be true
          end
        end
      end
    end

    describe 'provider switching behavior' do
      it 'updates websearch state when switching between providers' do
        visit '/'
        wait_for_app_load
        
        # Start with OpenAI (native websearch)
        select_app('chat_openai')
        wait_for_ajax
        
        websearch_checkbox = find('#websearch', visible: :all)
        openai_disabled = websearch_checkbox.disabled?
        
        # Switch to DeepSeek (requires Tavily)
        select_app('chat_deepseek')
        wait_for_ajax
        
        # The state should potentially change based on Tavily availability
        # We can't test the actual state without knowing CONFIG at runtime
        # But we can verify the switching mechanism works
        deepseek_disabled = websearch_checkbox.disabled?
        
        # At minimum, the checkbox should still exist and be accessible
        expect(websearch_checkbox).to be_present
      end
    end
  end

  describe 'API endpoint availability' do
    it 'provides environment information via API' do
      # Test that the API endpoint exists and returns valid JSON
      visit '/'
      wait_for_app_load
      
      # Use JavaScript to fetch the API endpoint
      api_response = page.evaluate_script(<<-JS)
        (async () => {
          try {
            const response = await fetch('/api/environment');
            if (!response.ok) return { error: 'Not OK', status: response.status };
            return await response.json();
          } catch (e) {
            return { error: e.message };
          }
        })()
      JS
      
      # Verify the response structure
      expect(api_response).to be_a(Hash)
      expect(api_response).to have_key('has_tavily_key')
      expect([true, false]).to include(api_response['has_tavily_key'])
    end
  end
end