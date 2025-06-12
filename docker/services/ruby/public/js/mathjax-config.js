window.MathJax = {
  startup: {
    typeset: false
  },
  tex: {
    inlineMath:  [ ['$', '$'], ['\\(', '\\)'] ],
    displayMath: [ ['$$', '$$'], ['\\[','\\]'] ],
    processEscapes: true,
    packages: {'[+]': ['ams', 'noerrors']},
    macros: {
      "R": "{\\mathbb{R}}",
      "N": "{\\mathbb{N}}",
      "Z": "{\\mathbb{Z}}",
      "Q": "{\\mathbb{Q}}",
      "C": "{\\mathbb{C}}",
      // Custom macro for multi-line boxed equations
      "mboxed": ["\\boxed{\\begin{array}{l} #1 \\end{array}}", 1]
    }
  },
  options: {
    skipHtmlTags: ["script", "noscript", "style", "textarea", "pre", "code"],
    renderActions: {
      addMenu: [],
      checkLoading: []
    }
  },
  chtml: {
    fontURL: './vendor/js/output/chtml/fonts/woff-v2',
    matchFontHeight: true,
    displayAlign: 'left',
    displayIndent: '0',
    scale: 1
  },
  svg: {
    fontCache: 'global',
    matchFontHeight: true,
    displayAlign: 'left',
    displayIndent: '0',
    scale: 1
  }
};