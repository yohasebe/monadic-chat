/**
 * Tests for VocabularyPanel.updateLiveValues — the client-side refresh of the
 * DOM-derived value tokens (MODEL/APP/LANG) on app/model switch (approach B).
 * Only concrete dropdown values are applied; ${LANG}=="auto" is left to the
 * server, and updateValues only touches rows that already exist in the panel.
 */
const VocabularyPanel = require("../../docker/services/ruby/public/js/monadic/vocabulary-panel.js");

function setupDom() {
  document.body.innerHTML = `
    <div id="available-variables" style="display:none;">
      <h5 id="available-variables-toggle"></h5>
      <div id="available-variables-list"></div>
    </div>
    <select id="model"><option value="gpt-5.3" selected>gpt-5.3</option></select>
    <select id="apps"><option value="ImageGeneratorOpenAI" selected>x</option></select>
    <select id="conversation-language"><option value="auto" selected>auto</option></select>
  `;
}

const ENTRIES = [
  { token: "MODEL", description: "model", display: "expand", value: null },
  { token: "APP", description: "app", display: "expand", value: null },
  { token: "LANG", description: "lang", display: "expand", value: null },
];

function valueOf(token) {
  const el = document.querySelector(
    '#available-variables-list [data-vocab-token="' + token + '"] .vocab-value'
  );
  return el ? el.textContent : null;
}

describe("VocabularyPanel.updateLiveValues", () => {
  afterEach(() => {
    delete window.apps;
    document.body.innerHTML = "";
  });

  test("fills ${MODEL} from #model and ${APP} from window.apps[key].display_name", () => {
    setupDom();
    window.apps = { ImageGeneratorOpenAI: { display_name: "Image Generator" } };
    VocabularyPanel.render(ENTRIES);

    VocabularyPanel.updateLiveValues();

    expect(valueOf("MODEL")).toBe("gpt-5.3");
    expect(valueOf("APP")).toBe("Image Generator");
  });

  test("leaves ${LANG} empty when conversation language is 'auto'", () => {
    setupDom();
    window.apps = {};
    VocabularyPanel.render(ENTRIES);

    VocabularyPanel.updateLiveValues();

    expect(valueOf("LANG")).toBe("");
  });

  test("applies a concrete ${LANG} value", () => {
    setupDom();
    window.apps = {};
    VocabularyPanel.render(ENTRIES);

    const langEl = document.getElementById("conversation-language");
    langEl.innerHTML = '<option value="ja" selected>ja</option>';
    langEl.value = "ja";

    VocabularyPanel.updateLiveValues();

    expect(valueOf("LANG")).toBe("ja");
  });

  test("is a no-op for tokens not present in the panel", () => {
    setupDom();
    window.apps = { ImageGeneratorOpenAI: { display_name: "Image Generator" } };
    // Render only a SHARED row — MODEL/APP rows are absent.
    VocabularyPanel.render([
      { token: "SHARED", description: "shared", display: "decorate", value: "/monadic/data" },
    ]);

    expect(() => VocabularyPanel.updateLiveValues()).not.toThrow();
    // No MODEL row was created.
    expect(
      document.querySelector('#available-variables-list [data-vocab-token="MODEL"]')
    ).toBeNull();
  });
});
