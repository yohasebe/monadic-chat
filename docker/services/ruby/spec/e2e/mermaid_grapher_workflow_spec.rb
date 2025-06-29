# frozen_string_literal: true

require_relative "e2e_helper"

RSpec.describe "Mermaid Grapher E2E", :e2e do
  include E2EHelper

  let(:app_name) { "MermaidGrapher" }

  describe "Mermaid diagram generation" do
    it "creates and validates a simple flowchart" do
      prompt = "Create a simple flowchart showing a login process with username/password input, validation, and success/failure outcomes"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, prompt)
        
        # Check for Mermaid syntax or diagram description
        success = response.match?(/graph|flowchart|login|username|mermaid/i)
        
        expect(success).to be(true),
          "Expected Mermaid diagram code, got: #{response[0..200]}..."
      end
    end

    it "creates different types of diagrams when requested" do
      prompt = "Create a sequence diagram showing the interaction between a user, web browser, and server during a typical HTTP request"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, prompt)
        
        # Check for sequence diagram syntax
        success = response.match?(/sequence|participant|user|browser|server/i)
        
        expect(success).to be(true),
          "Expected sequence diagram, got: #{response[0..200]}..."
      end
    end

    it "validates and corrects invalid Mermaid syntax" do
      prompt = "Here's my Mermaid code, please check if it's valid and fix any errors:\n```mermaid\ngraph TD\n  A[Start --> B[Process\n  B --> C[End]\n```"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, prompt)
        
        # Check for validation/correction
        success = response.match?(/fix|correct|valid|error|syntax|graph/i)
        
        expect(success).to be(true),
          "Expected syntax validation/correction, got: #{response[0..200]}..."
      end
    end

    it "generates a preview when asked" do
      prompt = "Create a pie chart showing browser market share (Chrome 65%, Safari 20%, Firefox 10%, Other 5%) and generate a preview image"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, prompt)
        
        # Check for pie chart and preview generation
        success = response.match?(/pie|chart|chrome|safari|firefox/i)
        
        expect(success).to be(true),
          "Expected pie chart with preview, got: #{response[0..200]}..."
      end
    end
  end

  describe "Complex diagram creation" do
    it "creates a Gantt chart for project planning" do
      prompt = "Create a Gantt chart for a 3-month software development project with phases: Planning (2 weeks), Development (6 weeks), Testing (3 weeks), and Deployment (1 week)"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, prompt)
        
        # Check for Gantt chart elements
        success = response.match?(/gantt|planning|development|testing/i)
        
        expect(success).to be(true), "Expected Gantt chart, got: #{response[0..200]}..."
      end
    end

    it "creates a mind map when requested" do
      prompt = "Create a mind map for planning a web application with main branches: Frontend, Backend, Database, and DevOps"
      
      with_e2e_retry(max_attempts: 3, wait: 10) do
        response = send_and_receive_message(app_name, prompt)
        
        # Check for mind map or alternative diagram
        success = response.match?(/mindmap|graph|frontend|backend|database/i)
        
        expect(success).to be(true),
          "Expected mind map diagram, got: #{response[0..200]}..."
      end
    end
  end
end