/**
 * Tests for model-capabilities.js
 *
 * Read-only capability query functions extracted from utilities.js.
 */

// Setup globals before requiring module
global.modelSpec = {
  'gpt-4o': {
    supports_pdf_upload: true,
    supports_file_inputs: true,
    api_type: 'responses'
  },
  'gpt-3.5-turbo': {
    supports_pdf: true,
    supports_file_inputs: false,
    api_type: 'chat'
  },
  'claude-sonnet-4-20250514': {
    supports_pdf_upload: false,
    supports_pdf: true
  },
  'legacy-model': {
    supports_pdf: true
  },
  'no-pdf': {}
};

global.apps = {
  'ImageGeneratorOpenAI': { image_generation: true },
  'ImageGeneratorGemini': { image_generation: true },
  'ImageGeneratorGrok': { image_generation: 'true' },
  'ChatOpenAI': { image_generation: false },
  'UploadOnlyApp': { image_generation: 'upload_only' }
};

global.$ = function(selector) {
  return { val: function() { return 'ChatOpenAI'; } };
};

const {
  isPdfSupportedForModel,
  isImageGenerationApp,
  isMaskEditingEnabled,
  isFileInputsSupportedForModel,
  isResponsesApiModel
} = require('../../docker/services/ruby/public/js/monadic/model-capabilities');

describe('model-capabilities', () => {
  describe('isPdfSupportedForModel', () => {
    it('returns true when supports_pdf_upload is true', () => {
      expect(isPdfSupportedForModel('gpt-4o')).toBe(true);
    });

    it('returns false when supports_pdf_upload is explicitly false', () => {
      expect(isPdfSupportedForModel('claude-sonnet-4-20250514')).toBe(false);
    });

    it('falls back to supports_pdf when supports_pdf_upload is absent', () => {
      expect(isPdfSupportedForModel('legacy-model')).toBe(true);
    });

    it('returns false when model has no pdf properties', () => {
      expect(isPdfSupportedForModel('no-pdf')).toBe(false);
    });

    it('returns false for unknown model', () => {
      expect(isPdfSupportedForModel('nonexistent')).toBe(false);
    });

    it('returns false for null/undefined', () => {
      expect(isPdfSupportedForModel(null)).toBe(false);
      expect(isPdfSupportedForModel(undefined)).toBe(false);
    });
  });

  describe('isImageGenerationApp', () => {
    it('returns true for image generation app', () => {
      expect(isImageGenerationApp('ImageGeneratorOpenAI')).toBe(true);
    });

    it('returns true for string "true" image_generation', () => {
      expect(isImageGenerationApp('ImageGeneratorGrok')).toBe(true);
    });

    it('returns false for non-image app', () => {
      expect(isImageGenerationApp('ChatOpenAI')).toBe(false);
    });

    it('returns false for unknown app', () => {
      expect(isImageGenerationApp('NonexistentApp')).toBe(false);
    });
  });

  describe('isMaskEditingEnabled', () => {
    it('returns true for standard image generation app', () => {
      expect(isMaskEditingEnabled('ImageGeneratorOpenAI')).toBe(true);
    });

    it('returns false for Gemini image generator', () => {
      expect(isMaskEditingEnabled('ImageGeneratorGemini')).toBe(false);
    });

    it('returns false for Grok image generator', () => {
      expect(isMaskEditingEnabled('ImageGeneratorGrok')).toBe(false);
    });

    it('returns false for upload_only apps', () => {
      expect(isMaskEditingEnabled('UploadOnlyApp')).toBe(false);
    });

    it('returns false for non-image apps', () => {
      expect(isMaskEditingEnabled('ChatOpenAI')).toBe(false);
    });
  });

  describe('isFileInputsSupportedForModel', () => {
    it('returns true when supports_file_inputs is true', () => {
      expect(isFileInputsSupportedForModel('gpt-4o')).toBe(true);
    });

    it('returns false when supports_file_inputs is false', () => {
      expect(isFileInputsSupportedForModel('gpt-3.5-turbo')).toBe(false);
    });

    it('returns false for unknown model', () => {
      expect(isFileInputsSupportedForModel('nonexistent')).toBe(false);
    });

    it('returns false for null', () => {
      expect(isFileInputsSupportedForModel(null)).toBe(false);
    });
  });

  describe('isResponsesApiModel', () => {
    it('returns true for responses API model', () => {
      expect(isResponsesApiModel('gpt-4o')).toBe(true);
    });

    it('returns false for chat API model', () => {
      expect(isResponsesApiModel('gpt-3.5-turbo')).toBe(false);
    });

    it('returns false for model without api_type', () => {
      expect(isResponsesApiModel('legacy-model')).toBe(false);
    });

    it('returns false for unknown model', () => {
      expect(isResponsesApiModel('nonexistent')).toBe(false);
    });
  });

  describe('exports', () => {
    it('exports all functions to window', () => {
      expect(window.isPdfSupportedForModel).toBe(isPdfSupportedForModel);
      expect(window.isImageGenerationApp).toBe(isImageGenerationApp);
      expect(window.isMaskEditingEnabled).toBe(isMaskEditingEnabled);
      expect(window.isFileInputsSupportedForModel).toBe(isFileInputsSupportedForModel);
      expect(window.isResponsesApiModel).toBe(isResponsesApiModel);
    });
  });
});
