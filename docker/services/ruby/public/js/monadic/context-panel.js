/**
 * Monadic Context Panel
 *
 * Displays session context for Monadic apps (read-only).
 * Context is updated in real-time via WebSocket after each AI response.
 * Supports dynamic schemas defined per-app in MDSL via context_schema block.
 */

const ContextPanel = {
  // State
  currentContext: null,
  currentSchema: null,
  isVisible: false,
  currentAppName: null,
  isLoading: false,

  // Default schema (used when app doesn't define context_schema)
  defaultSchema: {
    fields: [
      { name: "topics", icon: "fa-tags", label: "Topics", description: "Main subjects discussed" },
      { name: "people", icon: "fa-users", label: "People", description: "Names of people mentioned" },
      { name: "notes", icon: "fa-sticky-note", label: "Notes", description: "Important facts to remember" }
    ]
  },

  // DOM elements (cached on init)
  panel: null,
  sectionsContainer: null,

  /**
   * Initialize the context panel
   */
  init() {
    this.panel = document.getElementById("context-panel");
    this.sectionsContainer = document.getElementById("context-sections");

    if (!this.panel) {
      console.warn("[ContextPanel] Panel element not found");
      return;
    }

    // Hide edit buttons (editing disabled)
    const saveBtn = document.getElementById("context-save");
    const cancelBtn = document.getElementById("context-cancel");
    if (saveBtn) saveBtn.style.display = "none";
    if (cancelBtn) cancelBtn.style.display = "none";

    this.bindEvents();
    console.log("[ContextPanel] Initialized");
  },

  /**
   * Bind event handlers
   */
  bindEvents() {
    // Section toggle (event delegation)
    if (this.sectionsContainer) {
      this.sectionsContainer.addEventListener("click", (e) => {
        const header = e.target.closest(".context-section-header");
        if (header) {
          this.toggleSection(header);
          return;
        }

        // Turn label click - navigate to corresponding card
        const turnLabel = e.target.closest(".context-turn-label");
        if (turnLabel && turnLabel.dataset.turn) {
          const turn = parseInt(turnLabel.dataset.turn, 10);
          this.scrollToTurn(turn);
        }
      });
    }

    // Toggle all sections
    const toggleAllBtn = document.getElementById("context-toggle-all");
    if (toggleAllBtn) {
      toggleAllBtn.addEventListener("click", () => this.toggleAllSections());
    }
  },

  /**
   * Scroll to the assistant message card corresponding to the given turn number
   * @param {number} turn - The turn number (1-indexed)
   */
  scrollToTurn(turn) {
    // Get all assistant cards in the discourse area (excluding temp-card)
    const assistantCards = document.querySelectorAll('#discourse .card:not(#temp-card) .role-assistant');

    if (turn > 0 && turn <= assistantCards.length) {
      // Turn 1 = index 0, Turn 2 = index 1, etc.
      const targetCardBody = assistantCards[turn - 1];
      const targetCard = targetCardBody.closest('.card');

      if (targetCard) {
        // Scroll to the card with smooth animation
        targetCard.scrollIntoView({ behavior: 'smooth', block: 'start' });

        // Add a brief highlight effect
        targetCard.classList.add('context-highlight');
        setTimeout(() => {
          targetCard.classList.remove('context-highlight');
        }, 2000);

        console.log(`[ContextPanel] Scrolled to Turn ${turn}`);
      }
    } else {
      console.warn(`[ContextPanel] Turn ${turn} not found (total: ${assistantCards.length})`);
    }
  },

  /**
   * Show the context panel (called when a Monadic app is selected)
   * @param {string} appName - The name of the app being selected
   * @param {Object} schema - Optional context schema from app settings
   */
  show(appName, schema = null) {
    if (this.panel) {
      // Reset context when switching to a different app
      if (appName && appName !== this.currentAppName) {
        this.resetContext();
        this.currentAppName = appName;
        // Set schema if provided, otherwise use default
        this.currentSchema = schema || this.defaultSchema;
      }

      this.panel.style.display = "block";
      this.isVisible = true;

      // Show initial message if no context data yet
      if (!this.currentContext && this.sectionsContainer) {
        this.sectionsContainer.innerHTML =
          '<div class="text-muted fst-italic small p-2">Context will appear here as the conversation progresses...</div>';
      }
    }
  },

  /**
   * Hide the context panel (called when a non-Monadic app is selected)
   */
  hide() {
    if (this.panel) {
      this.panel.style.display = "none";
      this.isVisible = false;
      this.resetContext();
      this.hideLoading();
    }
  },

  /**
   * Show the loading indicator (blinking dot) while context is being extracted
   */
  showLoading() {
    if (!this.panel || !this.isVisible) return;

    this.isLoading = true;
    // Add loading indicator next to the header title
    const header = this.panel.querySelector("h5");
    if (header && !header.querySelector(".context-loading-indicator")) {
      const indicator = document.createElement("span");
      indicator.className = "context-loading-indicator";
      // Use i18n translation if available
      const tooltipText = typeof webUIi18n !== "undefined"
        ? webUIi18n.t("ui.messages.spinnerUpdatingContext")
        : "Updating context...";
      indicator.title = tooltipText;
      header.querySelector(".text")?.appendChild(indicator);
    }
  },

  /**
   * Hide the loading indicator
   */
  hideLoading() {
    this.isLoading = false;
    const indicator = this.panel?.querySelector(".context-loading-indicator");
    if (indicator) {
      indicator.remove();
    }
  },

  /**
   * Reset context data (called when switching apps or hiding panel)
   */
  resetContext() {
    this.currentContext = null;
    this.currentSchema = null;
    this.currentAppName = null;
    if (this.sectionsContainer) {
      this.sectionsContainer.innerHTML = "";
    }
    this.updateLegendVisibility(false);
  },

  /**
   * Update the visibility of the turn legend and its badge
   * @param {boolean} show - Whether to show the legend
   * @param {number} turnCount - Total number of turns (optional)
   */
  updateLegendVisibility(show, turnCount = 0) {
    const legend = document.getElementById("context-legend");
    const badge = document.getElementById("context-turn-badge");
    if (legend) {
      legend.style.display = show ? "flex" : "none";
    }
    if (badge) {
      badge.textContent = turnCount;
    }
  },

  /**
   * Update context from WebSocket message
   * @param {Object} context - The context object with dynamic keys
   * @param {Object} schema - Optional schema defining fields to display
   */
  updateContext(context, schema = null) {
    this.currentContext = context;
    // Update schema if provided
    if (schema) {
      this.currentSchema = schema;
    }
    if (this.isVisible) {
      this.render();
    }
  },

  /**
   * Get the effective schema (current schema or default)
   * @returns {Object} The schema to use for rendering
   */
  getEffectiveSchema() {
    return this.currentSchema || this.defaultSchema;
  },

  /**
   * Render the context sections
   */
  render() {
    if (!this.sectionsContainer || !this.currentContext) {
      return;
    }

    // Get schema fields
    const schema = this.getEffectiveSchema();
    const fields = schema.fields || this.defaultSchema.fields;

    // Check if there's any actual content
    const hasContent = fields.some(field => {
      const items = this.currentContext[field.name];
      return Array.isArray(items) && items.length > 0;
    });

    if (!hasContent) {
      this.sectionsContainer.innerHTML =
        '<div class="text-muted fst-italic small p-2">Context will appear here as the conversation progresses...</div>';
      this.updateLegendVisibility(false);
      return;
    }

    // Calculate total turn count across all items
    const allTurns = new Set();
    for (const field of fields) {
      const items = this.currentContext[field.name];
      if (Array.isArray(items)) {
        items.forEach(item => {
          const turn = typeof item === 'object' ? (item.turn || 1) : 1;
          allTurns.add(turn);
        });
      }
    }

    // Show legend with total turn count
    this.updateLegendVisibility(true, allTurns.size);

    let html = "";

    // Render sections in schema order
    for (const field of fields) {
      const items = this.currentContext[field.name];
      if (Array.isArray(items) && items.length > 0) {
        html += this.renderSection(field, items);
      }
    }

    this.sectionsContainer.innerHTML = html;
  },

  /**
   * Count unique turns in items
   * @param {Array} items - The items to count turns from
   * @returns {number} Number of unique turns
   */
  countUniqueTurns(items) {
    const turns = new Set();
    items.forEach(item => {
      const turn = typeof item === 'object' ? (item.turn || 1) : 1;
      turns.add(turn);
    });
    return turns.size;
  },

  /**
   * Render a single section based on schema field definition
   * @param {Object} field - The field definition from schema
   * @param {Array} items - The items in this section
   * @returns {string} HTML string
   */
  renderSection(field, items) {
    const displayName = field.label || this.formatDisplayName(field.name);
    const icon = field.icon || this.getIconForKey(field.name);
    const itemsArray = Array.isArray(items) ? items : items ? [items] : [];

    // Show number of items in badge (turn count is shown in legend)
    const itemCount = itemsArray.length;

    return `
      <div class="context-section" data-key="${this.escapeHtml(field.name)}">
        <div class="context-section-header d-flex align-items-center">
          <i class="fas ${icon} me-2"></i>
          <span class="flex-grow-1">${this.escapeHtml(displayName)}</span>
          <span class="badge bg-secondary context-badge">${itemCount}</span>
          <i class="fas fa-chevron-down ms-2 toggle-icon"></i>
        </div>
        <div class="context-section-content">
          ${this.renderItems(itemsArray)}
        </div>
      </div>
    `;
  },

  /**
   * Render items grouped by turn with separators
   * @param {Array} items - The items to render (can be strings or {text, turn, edited} objects)
   * @returns {string} HTML string
   */
  renderItems(items) {
    if (items.length === 0) {
      return "";
    }

    // Check if items have turn information
    const hasTurnInfo = items.some(item => typeof item === 'object' && item.turn !== undefined);

    if (!hasTurnInfo) {
      // Legacy format: display as comma-separated list
      const itemsText = items.map((item) => {
        const text = typeof item === 'object' ? item.text : String(item);
        return this.escapeHtml(text);
      }).join(", ");
      return `<div class="context-items-list">${itemsText}</div>`;
    }

    // New format: group by turn and display with separators
    const groupedByTurn = this.groupItemsByTurn(items);
    const turns = Object.keys(groupedByTurn).map(Number).sort((a, b) => b - a); // Descending order (newest first)

    let html = '<div class="context-items-grouped">';
    turns.forEach((turn, index) => {
      const turnItems = groupedByTurn[turn];
      const hasEditedItems = turnItems.some(item => item.edited);
      const itemsText = turnItems.map(item => this.escapeHtml(item.text)).join(", ");

      // Add edited badge if any item in this turn was edited
      const editedBadge = hasEditedItems
        ? '<span class="context-edited-badge" title="This turn was re-extracted after editing"><i class="fas fa-pen-to-square"></i></span>'
        : '';

      html += `
        <div class="context-turn-group${index > 0 ? ' with-separator' : ''}${hasEditedItems ? ' edited' : ''}">
          <span class="context-turn-label clickable" data-turn="${turn}" title="Click to jump to Turn ${turn}">T${turn}</span>${editedBadge}
          <span class="context-turn-items">${itemsText}</span>
        </div>
      `;
    });
    html += '</div>';

    return html;
  },

  /**
   * Group items by their turn number
   * @param {Array} items - The items with turn information
   * @returns {Object} Items grouped by turn number, preserving edited flag
   */
  groupItemsByTurn(items) {
    const grouped = {};
    items.forEach(item => {
      const turn = typeof item === 'object' ? (item.turn || 1) : 1;
      const text = typeof item === 'object' ? item.text : String(item);
      const edited = typeof item === 'object' ? (item.edited || false) : false;
      if (!grouped[turn]) {
        grouped[turn] = [];
      }
      grouped[turn].push({ text, turn, edited });
    });
    return grouped;
  },

  /**
   * Toggle a section's collapsed state
   * @param {HTMLElement} header - The section header element
   */
  toggleSection(header) {
    const section = header.closest(".context-section");
    if (section) {
      section.classList.toggle("collapsed");
    }
  },

  /**
   * Toggle all sections
   */
  toggleAllSections() {
    const sections =
      this.sectionsContainer?.querySelectorAll(".context-section");
    if (!sections || sections.length === 0) return;

    // Check if any section is expanded
    const anyExpanded = Array.from(sections).some(
      (s) => !s.classList.contains("collapsed")
    );

    // If any expanded, collapse all; otherwise expand all
    sections.forEach((section) => {
      if (anyExpanded) {
        section.classList.add("collapsed");
      } else {
        section.classList.remove("collapsed");
      }
    });
  },

  /**
   * Format a key name for display
   * @param {string} key - The key to format (e.g., "target_lang", "language_advice")
   * @returns {string} Formatted display name (e.g., "Target Lang", "Language Advice")
   */
  formatDisplayName(key) {
    return key
      .split("_")
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join(" ");
  },

  /**
   * Get an icon class for a context key (fallback when schema doesn't provide icon)
   * @param {string} key - The context key
   * @returns {string} Font Awesome icon class
   */
  getIconForKey(key) {
    const iconMap = {
      topics: "fa-tags",
      people: "fa-users",
      notes: "fa-sticky-note",
      images: "fa-image",
      generated_images: "fa-image",
      uploaded_images: "fa-image",
      files: "fa-file",
      code: "fa-code",
      links: "fa-link",
      urls: "fa-link",
      dates: "fa-calendar",
      locations: "fa-map-marker",
      tasks: "fa-tasks",
      questions: "fa-question",
      ideas: "fa-lightbulb",
      decisions: "fa-check-circle",
      styles: "fa-palette",
      style_preferences: "fa-palette",
      prompts: "fa-history",
      prompt_history: "fa-history",
      target_lang: "fa-language",
      language_advice: "fa-lightbulb",
      summary: "fa-file-alt",
      key_points: "fa-list-ul",
      references: "fa-link",
    };
    return iconMap[key] || "fa-circle";
  },

  /**
   * Escape HTML to prevent XSS
   * @param {string} str - The string to escape
   * @returns {string} Escaped string
   */
  escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  },
};

// Initialize when DOM is ready
document.addEventListener("DOMContentLoaded", () => {
  ContextPanel.init();
});

// Export for use in other modules
if (typeof window !== "undefined") {
  window.ContextPanel = ContextPanel;
}
