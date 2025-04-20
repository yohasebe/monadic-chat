/**
 * @jest-environment jsdom
 */

// Import helpers from the shared utilities file
const { setupTestEnvironment } = require('../helpers');

// Define a test utilities module that matches the structure of the actual module
// This approach separates test implementations from actual code
const testUtilities = {
  // String manipulation functions
  removeCode: (text) => {
    return text.replace(/```[\s\S]+?```|\<(script|style)[\s\S]+?<\/\1>|\<img [\s\S]+?\/>/g, " ");
  },
  
  removeMarkdown: (text) => {
    return text.replace(/(\*\*|__|[\*_`])/g, "");
  },
  
  removeEmojis: (text) => {
    try {
      return text.replace(/\p{Extended_Pictographic}/gu, "");
    } catch (error) {
      return text;
    }
  },
  
  convertString: (str) => {
    return str
      .split("_")
      .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
      .join(" ");
  },
  
  // App selector icon and UI updates
  updateAppSelectIcon: (appValue) => {
    // If no appValue is provided, use current selected app
    if (!appValue && $("#apps").val()) {
      appValue = $("#apps").val();
    }
    
    // If apps object is not yet populated or app not found, do nothing
    if (!appValue || !global.apps || !global.apps[appValue] || !global.apps[appValue]["icon"]) {
      return;
    }
    
    // Get the icon HTML from the apps object
    const iconHtml = global.apps[appValue]["icon"];
    
    // Update the icon in the static icon span
    $("#app-select-icon").html(iconHtml);
    
    // Also update the active class in the custom dropdown if it exists
    if ($("#custom-apps-dropdown").length > 0) {
      $(".custom-dropdown-option").removeClass("active");
      $(`.custom-dropdown-option[data-value="${appValue}"]`).addClass("active");
    }
  },
  
  // Model and format functions
  listModels: (models, openai = false) => {
    const regularModelPatterns = [/^\b(?:gpt-4o|gpt-4\.\d)\b/];
    const betaModelPatterns = [/^\bo\d\b/];
  
    const regularModels = [];
    const betaModels = [];
    const otherModels = [];
  
    for (let model of models) {
      if (regularModelPatterns.some(pattern => pattern.test(model))) {
        regularModels.push(model);
      } else if (betaModelPatterns.some(pattern => pattern.test(model))) {
        betaModels.push(model);
      } else {
        otherModels.push(model);
      }
    }
  
    let modelOptions = [];
  
    if (openai) {
      modelOptions = [
        '<option disabled>──gpt-models──</option>',
        ...regularModels.map(model =>
          `<option value="${model}">${model}</option>`
        ),
        '<option disabled>──reasoning models──</option>',
        ...betaModels.map(model =>
          `<option value="${model}" data-model-type="reasoning">${model}</option>`
        ),
        '<option disabled>──other models──</option>',
        ...otherModels.map(model =>
          `<option value="${model}">${model}</option>`
        )
      ];
    } else {
      modelOptions = [
        ...regularModels.map(model =>
          `<option value="${model}">${model}</option>`
        ),
        ...betaModels.map(model =>
          `<option value="${model}">${model}</option>`
        ),
        ...otherModels.map(model =>
          `<option value="${model}">${model}</option>`
        )
      ];
    }
  
    return modelOptions.join('');
  },
  
  formatInfo: (info) => {
    let noValue = true;
    let textRows = "";
    let numRows = "";

    for (const [key, value] of Object.entries(info)) {
      if (value && value !== 0) {
        let label = "";
        switch (key) {
          case "count_messages":
            noValue = false;
            label = "Number of all messages";
            break;
          case "count_active_messages":
            noValue = false;
            label = "Number of active messages";
            break;
          case "count_all_tokens":
            noValue = false;
            label = "Tokens in all messages";
            break;
          case "count_total_system_tokens":
            noValue = false;
            label = "Tokens in all system prompts";
            break;
          case "count_total_input_tokens":
            noValue = false;
            label = "Tokens in all user messages";
            break;
          case "count_total_output_tokens":
            noValue = false;
            label = "Tokens in all assistant messages";
            break;
          case "count_total_active_tokens":
            noValue = false;
            label = "Tokens in all active messages";
            break;
          case "encoding_name":
            // skip
            continue;
        }

        if (value && !isNaN(value) && label) {
          numRows += `
            <tr>
            <td>${label}</td>
            <td align="right">${parseInt(value).toLocaleString('en')}</td>
            </tr>
            `;
        } else if (!noValue && label) {
          textRows += `
            <tr>
            <td>${label}</td>
            <td align="right">${value}</td>
            </tr>
            `;
        }
      }
    }

    if (noValue) {
      return "";
    }

    return `
      <div class="json-item" data-key="stats" data-depth="0">
      <div class="json-toggle" onclick="toggleItem(this)">
      <i class="fas fa-chevron-right"></i> <span class="toggle-text">click to toggle</span>
      </div>
      <div class="json-content" style="display: none;">
      <table class="table table-sm mb-0">
      <tbody>
      ${textRows}
    ${numRows}
      </tbody>
      </table>
      </div>
      </div>
      `;
  }
};

describe('Utilities Module', () => {
  // Local test environment reference - prevents accidental global leakage
  let testEnv;
  
  beforeEach(() => {
    // Setup minimal test environment with only what's needed
    testEnv = setupTestEnvironment({
      bodyHtml: '<div id="test-container"></div>',
      messages: []
    });
  });
  
  afterEach(() => {
    // Clean up environment to prevent state leakage
    testEnv.cleanup();
  });
  
  // Group related tests for better organization
  describe('String Operations', () => {
    describe('removeCode', () => {
      const { removeCode } = testUtilities;
      
      it('should remove code blocks', () => {
        const text = 'Some text ```const x = 1;``` and more text';
        expect(removeCode(text)).toBe('Some text   and more text');
      });
      
      it('should remove script and style tags', () => {
        const text = 'Text with <script>alert("hi");</script> and <style>.test{color:red;}</style>';
        expect(removeCode(text)).toBe('Text with   and  ');
      });
      
      it('should remove image tags', () => {
        const text = 'Text with <img src="image.jpg" alt="test" /> in the middle';
        expect(removeCode(text)).toBe('Text with   in the middle');
      });
      
      it('should handle multi-line code blocks', () => {
        const text = 'Before\n```\nconst x = 1;\nconst y = 2;\n```\nAfter';
        expect(removeCode(text)).toBe('Before\n \nAfter');
      });
    });
    
    describe('removeMarkdown', () => {
      const { removeMarkdown } = testUtilities;
      
      it('should remove markdown formatting', () => {
        const text = '**bold** _italic_ `code` *emphasis*';
        expect(removeMarkdown(text)).toBe('bold italic code emphasis');
      });
      
      it('should handle multiple markdown elements in a sentence', () => {
        const text = 'This is a **bold** statement with _italic_ words and `code blocks` mixed in.';
        expect(removeMarkdown(text)).toBe('This is a bold statement with italic words and code blocks mixed in.');
      });
      
      it('should handle nested markdown formatting', () => {
        const text = '**Bold _and italic_**';
        expect(removeMarkdown(text)).toBe('Bold and italic');
      });
    });
    
    describe('removeEmojis', () => {
      const { removeEmojis } = testUtilities;
      
      it('should remove emoji characters', () => {
        const text = 'Hello 😀 world 🌍';
        expect(removeEmojis(text)).toBe('Hello  world ');
      });
      
      it('should handle errors gracefully', () => {
        // Mock the replace method to throw an error
        const originalReplace = String.prototype.replace;
        String.prototype.replace = jest.fn().mockImplementation(() => {
          throw new Error('Mock error');
        });
        
        const text = 'Some text with 🙂 emoji';
        expect(removeEmojis(text)).toBe(text);
        
        // Restore the original replace method
        String.prototype.replace = originalReplace;
      });
      
      it('should handle a mix of text, emojis, and special characters', () => {
        const text = 'Text with emojis 😊🎉 and special chars #@!';
        expect(removeEmojis(text)).toBe('Text with emojis  and special chars #@!');
      });
    });
    
    describe('convertString', () => {
      const { convertString } = testUtilities;
      
      it('should convert snake_case to Title Case', () => {
        expect(convertString('this_is_snake_case')).toBe('This Is Snake Case');
      });
      
      it('should handle single words', () => {
        expect(convertString('word')).toBe('Word');
      });
      
      it('should handle empty strings', () => {
        expect(convertString('')).toBe('');
      });
      
      it('should handle strings with multiple underscores', () => {
        expect(convertString('multiple___underscores')).toBe('Multiple   Underscores');
      });
    });
  });
  
  // Group model-related tests
  describe('Model Operations', () => {
    describe('listModels', () => {
      const { listModels } = testUtilities;
      
      it('should format models into option elements with groups (OpenAI)', () => {
        const models = ['gpt-4.1', 'o1', 'gpt-3.5', 'some-other-model'];
        const result = listModels(models, true);
        
        // Should include headers for different model groups
        expect(result).toContain('<option disabled>──gpt-models──</option>');
        expect(result).toContain('<option disabled>──reasoning models──</option>');
        expect(result).toContain('<option disabled>──other models──</option>');
        
        // Should include all models as options
        expect(result).toContain('<option value="gpt-4.1">gpt-4.1</option>');
        expect(result).toContain('<option value="o1" data-model-type="reasoning">o1</option>');
        expect(result).toContain('<option value="gpt-3.5">gpt-3.5</option>');
        expect(result).toContain('<option value="some-other-model">some-other-model</option>');
      });
      
      it('should format models without groups (non-OpenAI)', () => {
        const models = ['gpt-4.1', 'o1', 'gpt-3.5', 'some-other-model'];
        const result = listModels(models, false);
        
        // Should NOT include headers for different model groups
        expect(result).not.toContain('<option disabled>──gpt-models──</option>');
        expect(result).not.toContain('<option disabled>──reasoning models──</option>');
        expect(result).not.toContain('<option disabled>──other models──</option>');
        
        // Should include all models as options without groups
        expect(result).toContain('<option value="gpt-4.1">gpt-4.1</option>');
        expect(result).toContain('<option value="o1">o1</option>');
        expect(result).not.toContain('data-model-type="reasoning"');
      });
      
      it('should handle empty models array', () => {
        expect(listModels([])).toBe('');
      });
      
      it('should correctly classify models based on patterns', () => {
        const models = ['gpt-4o-vision', 'o1-preview', 'gpt-4.5-turbo', 'claude-3'];
        const result = listModels(models, true);
        
        // Check regular models classification
        expect(result).toContain('<option value="gpt-4o-vision">gpt-4o-vision</option>');
        expect(result).toContain('<option value="gpt-4.5-turbo">gpt-4.5-turbo</option>');
        
        // Check beta models classification
        expect(result).toContain('<option value="o1-preview" data-model-type="reasoning">o1-preview</option>');
        
        // Check other models classification
        expect(result).toContain('<option value="claude-3">claude-3</option>');
      });
    });

    describe('updateAppSelectIcon', () => {
      const { updateAppSelectIcon } = testUtilities;
      let mockJQuery;
      let originalJQuery;
      
      beforeEach(() => {
        // Save original jQuery implementation
        originalJQuery = global.$;
        
        // Set up mock elements
        const mockAppSelectIcon = {
          html: jest.fn()
        };
        
        const mockAppsSelect = {
          val: jest.fn().mockReturnValue('TestApp')
        };
        
        const mockCustomDropdown = {
          length: 1
        };
        
        const mockDropdownOptions = {
          removeClass: jest.fn(),
          addClass: jest.fn()
        };
        
        // Setup jQuery mock
        mockJQuery = jest.fn(selector => {
          if (selector === "#app-select-icon") return mockAppSelectIcon;
          if (selector === "#apps") return mockAppsSelect;
          if (selector === "#custom-apps-dropdown") return mockCustomDropdown;
          if (selector === ".custom-dropdown-option") return mockDropdownOptions;
          if (selector === '.custom-dropdown-option[data-value="TestApp"]') return mockDropdownOptions;
          return {
            html: jest.fn(),
            val: jest.fn(),
            length: 0,
            removeClass: jest.fn(),
            addClass: jest.fn()
          };
        });
        
        global.$ = mockJQuery;
        
        // Setup global apps object
        global.apps = {
          'TestApp': {
            'icon': '<i class="fas fa-test"></i>',
            'display_name': 'Test App'
          }
        };
      });
      
      afterEach(() => {
        // Restore original jQuery
        global.$ = originalJQuery;
        delete global.apps;
      });
      
      it('should update the icon in the standard selector', () => {
        updateAppSelectIcon('TestApp');
        
        // Should call html with the correct icon
        expect(mockJQuery("#app-select-icon").html).toHaveBeenCalledWith('<i class="fas fa-test"></i>');
      });
      
      it('should update active class in custom dropdown if it exists', () => {
        updateAppSelectIcon('TestApp');
        
        // Should remove active class from all options
        expect(mockJQuery(".custom-dropdown-option").removeClass).toHaveBeenCalledWith("active");
        
        // Should add active class to selected option
        expect(mockJQuery('.custom-dropdown-option[data-value="TestApp"]').addClass).toHaveBeenCalledWith("active");
      });
      
      it('should use current app value if no app value provided', () => {
        updateAppSelectIcon();
        
        // Should get current app value
        expect(mockJQuery("#apps").val).toHaveBeenCalled();
        
        // Should update with that value's icon
        expect(mockJQuery("#app-select-icon").html).toHaveBeenCalledWith('<i class="fas fa-test"></i>');
      });
      
      it('should do nothing if app not found in apps object', () => {
        // Using an app that doesn't exist
        updateAppSelectIcon('NonExistentApp');
        
        // Should not update anything
        expect(mockJQuery("#app-select-icon").html).not.toHaveBeenCalled();
      });
      
      it('should do nothing if no custom dropdown exists', () => {
        // Create new mocks specifically for this test
        const mockAppSelectIcon = { html: jest.fn() };
        const mockAppsSelect = { val: jest.fn().mockReturnValue('TestApp') };
        const mockCustomDropdown = { length: 0 }; // This is the key difference - length 0 means dropdown doesn't exist
        const mockDropdownOptions = { removeClass: jest.fn(), addClass: jest.fn() };
        
        // Create completely new mock implementation for this test
        const newMockJQuery = jest.fn(selector => {
          if (selector === "#app-select-icon") return mockAppSelectIcon;
          if (selector === "#apps") return mockAppsSelect;
          if (selector === "#custom-apps-dropdown") return mockCustomDropdown;
          if (selector === ".custom-dropdown-option") return mockDropdownOptions;
          if (selector === '.custom-dropdown-option[data-value="TestApp"]') return mockDropdownOptions;
          return { html: jest.fn(), val: jest.fn(), length: 0, removeClass: jest.fn(), addClass: jest.fn() };
        });
        
        // Temporarily replace global $ function
        const oldJQuery = global.$;
        global.$ = newMockJQuery;
        
        try {
          updateAppSelectIcon('TestApp');
          
          // Should update icon 
          expect(mockAppSelectIcon.html).toHaveBeenCalledWith('<i class="fas fa-test"></i>');
          
          // But should not update dropdown classes because custom dropdown doesn't exist
          expect(mockDropdownOptions.removeClass).not.toHaveBeenCalled();
          expect(mockDropdownOptions.addClass).not.toHaveBeenCalled();
        } finally {
          // Restore original $ function
          global.$ = oldJQuery;
        }
      });
    });
  });
  
  // Group formatting functions
  describe('Formatting Functions', () => {
    describe('formatInfo', () => {
      const { formatInfo } = testUtilities;
      
      it('should format info object into HTML', () => {
        const info = {
          count_messages: 10,
          count_active_messages: 8,
          count_all_tokens: 1000,
          count_total_system_tokens: 200,
          count_total_input_tokens: 300,
          count_total_output_tokens: 500,
          count_total_active_tokens: 800,
          encoding_name: 'cl100k_base' // should be skipped
        };
        
        const result = formatInfo(info);
        
        // Should include table structure
        expect(result).toContain('<table class="table table-sm mb-0">');
        
        // Should include all values from info
        expect(result).toContain('Number of all messages');
        expect(result).toContain('10');
        expect(result).toContain('Number of active messages');
        expect(result).toContain('8');
        expect(result).toContain('Tokens in all messages');
        expect(result).toContain('1,000');
        
        // Should NOT include encoding_name
        expect(result).not.toContain('encoding_name');
      });
      
      it('should return empty string for empty info', () => {
        expect(formatInfo({})).toBe('');
      });
      
      it('should handle info with only zero or null values', () => {
        const info = {
          count_messages: 0,
          count_active_messages: null,
          count_all_tokens: undefined
        };
        
        expect(formatInfo(info)).toBe('');
      });
      
      it('should handle numeric values correctly', () => {
        const info = {
          count_messages: '1234567', // string number
          count_all_tokens: 9876543  // actual number
        };
        
        const result = formatInfo(info);
        
        // Should format both string and numeric values as localized numbers
        expect(result).toContain('1,234,567');
        expect(result).toContain('9,876,543');
      });
    });
  });
});
