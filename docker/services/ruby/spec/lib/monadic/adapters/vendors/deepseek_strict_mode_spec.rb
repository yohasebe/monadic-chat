# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../../lib/monadic/adapters/vendors/deepseek_helper"

# Mock CONFIG if not already loaded
unless defined?(CONFIG)
  CONFIG = {}
end

RSpec.describe "DeepSeek Strict Function Calling" do
  describe "DeepSeekHelper.convert_to_strict_tools" do
    it "adds strict flag to function definitions" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "test_function",
            "description" => "A test function",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "param1" => { "type" => "string" }
              }
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      
      expect(strict_tools[0]["function"]["strict"]).to eq(true)
    end
    
    it "sets additionalProperties to false for all objects" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "test_function",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "param1" => { "type" => "string" },
                "nested" => {
                  "type" => "object",
                  "properties" => {
                    "inner" => { "type" => "string" }
                  }
                }
              }
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      params = strict_tools[0]["function"]["parameters"]
      
      expect(params["additionalProperties"]).to eq(false)
      expect(params["properties"]["nested"]["additionalProperties"]).to eq(false)
    end
    
    it "ensures ALL properties are in required array" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "test_function",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "param1" => { "type" => "string" },
                "param2" => { "type" => "integer" },
                "param3" => { "type" => "boolean" }
              },
              "required" => ["param1"]  # Originally only param1 was required
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      params = strict_tools[0]["function"]["parameters"]
      
      # In strict mode, ALL properties must be required
      expect(params["required"]).to match_array(["param1", "param2", "param3"])
    end
    
    it "processes nested objects recursively" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "complex_function",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "outer" => {
                  "type" => "object",
                  "properties" => {
                    "middle" => {
                      "type" => "object",
                      "properties" => {
                        "inner" => { "type" => "string" },
                        "value" => { "type" => "number" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      outer = strict_tools[0]["function"]["parameters"]["properties"]["outer"]
      middle = outer["properties"]["middle"]
      
      expect(outer["additionalProperties"]).to eq(false)
      expect(outer["required"]).to eq(["middle"])
      expect(middle["additionalProperties"]).to eq(false)
      expect(middle["required"]).to match_array(["inner", "value"])
    end
    
    it "handles array items schemas" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "array_function",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "items" => {
                  "type" => "array",
                  "items" => {
                    "type" => "object",
                    "properties" => {
                      "id" => { "type" => "string" },
                      "name" => { "type" => "string" }
                    }
                  }
                }
              }
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      array_items = strict_tools[0]["function"]["parameters"]["properties"]["items"]["items"]
      
      expect(array_items["additionalProperties"]).to eq(false)
      expect(array_items["required"]).to match_array(["id", "name"])
    end
    
    it "handles anyOf schemas" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "anyof_function",
            "parameters" => {
              "type" => "object",
              "properties" => {
                "value" => {
                  "anyOf" => [
                    {
                      "type" => "object",
                      "properties" => {
                        "stringValue" => { "type" => "string" }
                      }
                    },
                    {
                      "type" => "object",
                      "properties" => {
                        "numberValue" => { "type" => "number" }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      anyof_schemas = strict_tools[0]["function"]["parameters"]["properties"]["value"]["anyOf"]
      
      expect(anyof_schemas[0]["additionalProperties"]).to eq(false)
      expect(anyof_schemas[0]["required"]).to eq(["stringValue"])
      expect(anyof_schemas[1]["additionalProperties"]).to eq(false)
      expect(anyof_schemas[1]["required"]).to eq(["numberValue"])
    end
    
    it "skips tools that already have strict property" do
      tools = [
        {
          "type" => "function",
          "function" => {
            "name" => "already_strict",
            "strict" => true,
            "parameters" => {
              "type" => "object",
              "properties" => {
                "param" => { "type" => "string" }
              }
              # No required array or additionalProperties
            }
          }
        }
      ]
      
      strict_tools = DeepSeekHelper.convert_to_strict_tools(tools)
      params = strict_tools[0]["function"]["parameters"]
      
      # Should not modify if already strict
      expect(params["required"]).to be_nil
      expect(params["additionalProperties"]).to be_nil
    end
  end
  
  describe "DeepSeekHelper.use_strict_mode?" do
    it "returns true for deepseek-chat model by default" do
      obj = { "model" => "deepseek-chat" }
      expect(DeepSeekHelper.use_strict_mode?(obj)).to eq(true)
    end
    
    it "returns false for deepseek-reasoner model" do
      obj = { "model" => "deepseek-reasoner" }
      expect(DeepSeekHelper.use_strict_mode?(obj)).to eq(false)
    end
    
    it "returns false when explicitly disabled" do
      obj = { "model" => "deepseek-chat", "strict_function_calling" => false }
      expect(DeepSeekHelper.use_strict_mode?(obj)).to eq(false)
    end
    
    it "returns true when forced via config" do
      # Temporarily set config
      original_value = CONFIG["DEEPSEEK_STRICT_MODE"]
      CONFIG["DEEPSEEK_STRICT_MODE"] = true
      
      obj = { "model" => "deepseek-reasoner" }  # Normally would be false
      expect(DeepSeekHelper.use_strict_mode?(obj)).to eq(true)
      
      # Restore original value
      if original_value.nil?
        CONFIG.delete("DEEPSEEK_STRICT_MODE")
      else
        CONFIG["DEEPSEEK_STRICT_MODE"] = original_value
      end
    end
  end
  
  describe "DeepSeekHelper.ensure_strict_schema" do
    it "handles deeply nested structures" do
      schema = {
        "type" => "object",
        "properties" => {
          "level1" => {
            "type" => "object",
            "properties" => {
              "level2" => {
                "type" => "array",
                "items" => {
                  "type" => "object",
                  "properties" => {
                    "level3" => {
                      "anyOf" => [
                        {
                          "type" => "object",
                          "properties" => {
                            "value" => { "type" => "string" }
                          }
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      }
      
      DeepSeekHelper.ensure_strict_schema(schema)
      
      expect(schema["additionalProperties"]).to eq(false)
      expect(schema["required"]).to eq(["level1"])
      
      level1 = schema["properties"]["level1"]
      expect(level1["additionalProperties"]).to eq(false)
      expect(level1["required"]).to eq(["level2"])
      
      level2_items = level1["properties"]["level2"]["items"]
      expect(level2_items["additionalProperties"]).to eq(false)
      expect(level2_items["required"]).to eq(["level3"])
      
      anyof_schema = level2_items["properties"]["level3"]["anyOf"][0]
      expect(anyof_schema["additionalProperties"]).to eq(false)
      expect(anyof_schema["required"]).to eq(["value"])
    end
  end
end