# frozen_string_literal: true

require_relative "../../spec_helper"

RSpec.describe "MDSL Protocol Consistency" do
  let(:apps_dir) { File.expand_path("../../../apps", __dir__) }
  let(:mdsl_files) { Dir.glob(File.join(apps_dir, "**", "*.mdsl")) }

  # Some apps reference shared constants (e.g., MathTutor::SYSTEM_PROMPT)
  # defined in *_constants.rb files. This helper reads the MDSL content and,
  # if the system prompt is a constant reference, also reads the constants file.
  def effective_content(mdsl_file)
    content = File.read(mdsl_file)
    app_dir = File.dirname(mdsl_file)
    constants_files = Dir.glob(File.join(app_dir, "*_constants.rb"))
    constants_content = constants_files.map { |f| File.read(f) }.join("\n")
    content + "\n" + constants_content
  end

  describe "Plan-Approve-Execute Protocol" do
    let(:apps_with_planning_import) do
      mdsl_files.select { |f| File.read(f).include?("import_shared_tools :planning") }
    end

    it "has at least one app with planning tools" do
      expect(apps_with_planning_import).not_to be_empty
    end

    it "includes propose_plan in effective system prompt for apps that import planning" do
      apps_with_planning_import.each do |file|
        content = effective_content(file)
        expect(content).to include("propose_plan"),
          "#{File.basename(file)} imports :planning but does not mention propose_plan in system prompt"
      end
    end

    it "includes Plan-Approve-Execute protocol section for apps that import planning" do
      apps_with_planning_import.each do |file|
        content = effective_content(file)
        has_protocol = content.match?(/Plan-Approve-Execute/i) ||
                       (content.include?("PLAN") && content.include?("APPROVE") && content.include?("EXECUTE"))
        expect(has_protocol).to be(true),
          "#{File.basename(file)} imports :planning but missing Plan-Approve-Execute protocol"
      end
    end

    it "specifies WHEN TO USE and WHEN TO SKIP for planning" do
      apps_with_planning_import.each do |file|
        content = effective_content(file)
        has_guidance = content.match?(/WHEN TO USE/i) && content.match?(/WHEN TO SKIP/i)
        expect(has_guidance).to be(true),
          "#{File.basename(file)} imports :planning but missing WHEN TO USE/SKIP guidance"
      end
    end
  end

  describe "Self-Verification Protocol" do
    let(:apps_with_verification_import) do
      mdsl_files.select { |f| File.read(f).include?("import_shared_tools :verification") }
    end

    it "has at least one app with verification tools" do
      expect(apps_with_verification_import).not_to be_empty
    end

    it "includes report_verification in effective system prompt for apps that import verification" do
      apps_with_verification_import.each do |file|
        content = effective_content(file)
        expect(content).to include("report_verification"),
          "#{File.basename(file)} imports :verification but does not mention report_verification"
      end
    end

    it "includes Self-Verification protocol section for apps that import verification" do
      apps_with_verification_import.each do |file|
        content = effective_content(file)
        has_protocol = content.match?(/Self-Verification/i) ||
                       content.match?(/VERIFICATION PASSED|ISSUES FOUND|report_verification/i)
        expect(has_protocol).to be(true),
          "#{File.basename(file)} imports :verification but missing Self-Verification protocol"
      end
    end

    it "specifies verification status values (passed, issues_found, fixed)" do
      apps_with_verification_import.each do |file|
        content = effective_content(file)
        expect(content).to include("passed"),
          "#{File.basename(file)} imports :verification but does not mention 'passed' status"
        expect(content).to include("issues_found"),
          "#{File.basename(file)} imports :verification but does not mention 'issues_found' status"
        expect(content).to include("fixed"),
          "#{File.basename(file)} imports :verification but does not mention 'fixed' status"
      end
    end

    it "limits maximum verification attempts" do
      apps_with_verification_import.each do |file|
        content = effective_content(file)
        has_limit = content.match?(/maximum\s+\d+\s+verification/i) ||
                    content.match?(/\d+\s+verification attempts/i)
        expect(has_limit).to be(true),
          "#{File.basename(file)} imports :verification but does not specify maximum verification attempts"
      end
    end
  end

  describe "Consistency between planning and verification imports" do
    it "apps with verification also have planning (verification is a subset)" do
      planning_files = mdsl_files.select { |f| File.read(f).include?("import_shared_tools :planning") }
      verification_files = mdsl_files.select { |f| File.read(f).include?("import_shared_tools :verification") }

      verification_files.each do |file|
        expect(planning_files).to include(file),
          "#{File.basename(file)} imports :verification but not :planning"
      end
    end
  end
end
