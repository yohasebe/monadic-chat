window.MathJax = {
  startup: {
    typeset: false,
    pageReady: () => {
      // Configure MathJax to process headers as well
      MathJax.startup.document.options.skipHtmlTags = 
        ["script", "noscript", "style", "textarea", "pre", "code"];
      // Remove default header tags from skip list
      MathJax.startup.document.options.ignoreHtmlTags = [];
    }
  },
  tex: {
    inlineMath:  [ ['$', '$'], ['\\(', '\\)'] ],
    displayMath: [ 
      ['$$', '$$'], 
      ['\\[','\\]'],
      ['\\begin{equation}', '\\end{equation}'],
      ['\\begin{equation*}', '\\end{equation*}'],
      ['\\begin{align}', '\\end{align}'],
      ['\\begin{align*}', '\\end{align*}'],
      ['\\begin{gather}', '\\end{gather}'],
      ['\\begin{gather*}', '\\end{gather*}'],
      ['\\begin{alignat}', '\\end{alignat}'],
      ['\\begin{alignat*}', '\\end{alignat*}']
    ],
    processEscapes: true,
    processEnvironments: true,
    packages: {'[+]': ['ams', 'noerrors']},
    tags: 'ams',
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
    processHtmlClass: 'mathjax-process',
    ignoreHtmlClass: 'mathjax-ignore',
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