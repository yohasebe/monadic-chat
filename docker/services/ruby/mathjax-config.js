window.MathJax = {
  startup: {
    typeset: false
  },
  tex: {
    inlineMath:  [ ['$', '$'], ['\\(', '\\)'] ],
    displayMath: [ ['$$', '$$'], ['\\[','\\]'] ],
    processEscapes: true,
    packages: {'[+]': ['ams']}
  },
  options: {
    skipHtmlTags: ["script", "noscript", "style", "textarea", "pre", "code"]
  },
  chtml: {
    matchFontHeight: false,
    displayAlign: 'left',
    displayIndent: '0',
    scale: 1.25,
    fontFamily: 'STIX-Web',
    availableFonts: ['STIX-Web']
  },
  svg: {
    matchFontHeight: false,
    displayAlign: 'left',
    displayIndent: '0',
    scale: 1.25,
    fontFamily: 'STIX-Web',
    availableFonts: ['STIX-Web']
  }
};
