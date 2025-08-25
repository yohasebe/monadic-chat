const fs = require('fs');
const path = require('path');

class I18n {
  constructor() {
    this.translations = {};
    this.currentLanguage = 'en';
    this.loadTranslations();
  }

  loadTranslations() {
    const languages = ['en', 'ja', 'zh', 'ko', 'es', 'fr', 'de'];
    
    languages.forEach(lang => {
      try {
        const translationsDir = path.join(__dirname, 'translations');
        const filePath = path.join(translationsDir, `${lang}.json`);
        
        // Check if translations directory and file exist
        if (fs.existsSync(filePath)) {
          const data = fs.readFileSync(filePath, 'utf8');
          this.translations[lang] = JSON.parse(data);
        } else {
          console.warn(`Translation file not found for ${lang}: ${filePath}`);
        }
      } catch (error) {
        console.error(`Failed to load translation for ${lang}:`, error);
      }
    });
    
    // Ensure at least English is loaded
    if (!this.translations['en']) {
      console.error('Failed to load English translations, using defaults');
      this.translations['en'] = {
        menu: { file: 'File', settings: 'Settings', quit: 'Quit' },
        tray: { show: 'Show', quit: 'Quit' },
        dialogs: { ok: 'OK', cancel: 'Cancel', error: 'Error' }
      };
    }
  }

  setLanguage(language) {
    if (this.translations[language]) {
      this.currentLanguage = language;
      return true;
    }
    console.warn(`Language ${language} not found, using English`);
    this.currentLanguage = 'en';
    return false;
  }

  getLanguage() {
    return this.currentLanguage;
  }

  t(key, replacements = {}) {
    const keys = key.split('.');
    let value = this.translations[this.currentLanguage];
    
    // Fallback to English if current language doesn't have the key
    let fallback = this.translations['en'];
    
    for (const k of keys) {
      value = value?.[k];
      fallback = fallback?.[k];
      
      if (!value && !fallback) {
        return key; // Return the key itself if translation not found
      }
    }
    
    let result = value || fallback || key;
    
    // Replace placeholders like {{version}}
    Object.keys(replacements).forEach(placeholder => {
      const regex = new RegExp(`{{${placeholder}}}`, 'g');
      result = result.replace(regex, replacements[placeholder]);
    });
    
    return result;
  }

  // Get all translations for a specific section (e.g., 'menu')
  getSection(section) {
    return this.translations[this.currentLanguage]?.[section] || 
           this.translations['en']?.[section] || {};
  }

  // Get available languages
  getAvailableLanguages() {
    return Object.keys(this.translations);
  }
}

// Export singleton instance
module.exports = new I18n();