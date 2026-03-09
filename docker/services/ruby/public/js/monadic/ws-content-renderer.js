/**
 * ws-content-renderer.js
 *
 * Content rendering utilities extracted from websocket.js:
 * MathJax, Mermaid, ABC notation, copy-code buttons, message rendering,
 * toggle/source-code helpers.
 */
(function() {
  "use strict";

  // ── Message rendering helpers ──────────────────────────────────────

  function getMessageAppName(msg) {
    if (msg && msg.app_name) {
      return msg.app_name;
    }

    if (window.SessionState && typeof window.SessionState.getCurrentApp === 'function') {
      var current = window.SessionState.getCurrentApp();
      if (current) return current;
    }

    if (typeof params !== 'undefined' && params && params["app_name"]) {
      return params["app_name"];
    }

    return null;
  }

  function getMessageMonadicFlag(msg) {
    if (msg && typeof msg.monadic !== 'undefined') {
      return msg.monadic;
    }

    if (typeof params !== 'undefined' && params && typeof params["monadic"] !== 'undefined') {
      return params["monadic"];
    }

    if (window.SessionState && window.SessionState.app && window.SessionState.app.params) {
      var appParams = window.SessionState.app.params;
      if (typeof appParams["monadic"] !== 'undefined') {
        return appParams["monadic"];
      }
    }

    return false;
  }

  function renderMessage(msg) {
    if (!msg) {
      console.error('renderMessage: msg is null or undefined');
      return '';
    }

    var appName = getMessageAppName(msg);
    var monadicFlag = getMessageMonadicFlag(msg);

    // Priority 1: Client-side rendering with MarkdownRenderer
    if (msg.text && window.MarkdownRenderer) {
      try {
        var result = window.MarkdownRenderer.render(msg.text, { appName: appName, isMonadic: monadicFlag });
        return result;
      } catch (err) {
        console.error('MarkdownRenderer failed:', err);
      }
    }

    // Priority 2: Server-rendered HTML (backward compatibility)
    if (msg.html) {
      return msg.html;
    }

    // Priority 3: Plain text fallback
    if (msg.text) {
      return msg.text;
    }

    // Last resort: empty string
    console.warn('Message ' + (msg.mid || '?') + ' has no renderable content');
    return '';
  }

  // ── Copy code button ───────────────────────────────────────────────

  function setCopyCodeButton(element) {
    if (!element) {
      return;
    }
    element.find("div.card-text div.highlighter-rouge").each(function () {
      var highlighterElement = $(this);
      if (highlighterElement.find(".copy-code-button").length === 0) {
        var codeElement = highlighterElement.find("code");
        if (codeElement.length) {
          var copyButton = $('<div class="copy-code-button"><i class="fa-solid fa-copy"></i></div>');
          highlighterElement.append(copyButton);

          copyButton.click(function () {
            var text = codeElement.text();
            var icon = copyButton.find("i");

            try {
              var textarea = document.createElement('textarea');
              textarea.value = text;
              textarea.style.position = 'fixed';
              textarea.style.opacity = 0;
              document.body.appendChild(textarea);
              textarea.select();

              var success = document.execCommand('copy');
              document.body.removeChild(textarea);

              if (!success) {
                throw new Error('execCommand copy failed');
              }

              icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
              setTimeout(function() {
                icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
              }, 1000);
            } catch (err) {
              console.error("Failed to copy text: ", err);

              try {
                if (window.electronAPI && typeof window.electronAPI.writeClipboard === 'function') {
                  window.electronAPI.writeClipboard(text);
                  icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
                  setTimeout(function() {
                    icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
                  }, 1000);
                } else if (navigator.clipboard && navigator.clipboard.writeText) {
                  navigator.clipboard.writeText(text)
                    .then(function() {
                      icon.removeClass("fa-copy").addClass("fa-check").css("color", "#DC4C64");
                      setTimeout(function() {
                        icon.removeClass("fa-check").addClass("fa-copy").css("color", "");
                      }, 1000);
                    })
                    .catch(function() {
                      icon.removeClass("fa-copy").addClass("fa-xmark").css("color", "#DC4C64");
                      setTimeout(function() {
                        icon.removeClass("fa-xmark").addClass("fa-copy").css("color", "");
                      }, 1000);
                    });
                } else {
                  throw new Error('No clipboard API available');
                }
              } catch (fallbackErr) {
                console.error("All clipboard methods failed: ", fallbackErr);
                icon.removeClass("fa-copy").addClass("fa-xmark").css("color", "#DC4C64");
                setTimeout(function() {
                  icon.removeClass("fa-xmark").addClass("fa-copy").css("color", "");
                }, 1000);
              }
            }
          });
        }
      }
    });
  }

  // ── MathJax ────────────────────────────────────────────────────────

  function applyMathJax(element) {
    if (element.hasClass("diagram")) {
      return;
    }

    if (typeof MathJax === 'undefined') {
      console.error('MathJax is not loaded. Please make sure to include the MathJax script in your HTML file.');
      return;
    }

    var domElement = element.get(0);
    MathJax.typesetPromise([domElement])
      .then(function() {})
      .catch(function(err) {
        console.error('Error re-rendering MathJax element:', err);
      });
  }

  // ── Mermaid ────────────────────────────────────────────────────────

  var mermaid_config = {
    startOnLoad: true,
    securityLevel: 'strict',
    theme: 'default'
  };

  function sanitizeMermaidSource(text) {
    if (!text) {
      return text;
    }

    return text
      .replace(/\r\n/g, '\n')
      .replace(/\\n/g, '\n')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/[\u2010-\u2015\u2212\u30FC\uFF0D]/g, '-')
      .replace(/[\u2018\u2019\u2032\uFF07]/g, "'")
      .replace(/[\u201C\u201D\u2033\uFF02]/g, '"')
      .replace(/[\u300C\u300D]/g, '"');
  }

  async function applyMermaid(element) {
    // Lazy-load Mermaid on first use
    if (window.LazyLoader) await window.LazyLoader.mermaid();
    if (typeof mermaid === 'undefined') return;
    mermaid.initialize(mermaid_config);

    element.find(".mermaid-code").each(function (index) {
      var mermaidElement = $(this);
      mermaidElement.addClass("sourcecode");
      mermaidElement.find("pre").addClass("sourcecode");
      var mermaidText = mermaidElement.text().trim();
      var sanitizedMermaidText = sanitizeMermaidSource(mermaidText);
      mermaidElement.find("pre").text(mermaidText);
      addToggleSourceCode(mermaidElement, "Toggle Mermaid Diagram");

      var containerId = 'diagram-' + index;
      var diagramContainer = $('<div class="diagram-wrapper">' +
        '<div class="diagram" id="' + containerId + '"><mermaid>' + sanitizedMermaidText + '</mermaid></div>' +
        '<div class="error-message" id="error-' + containerId + '" style="display: none;"></div>' +
        '</div>');
      mermaidElement.after(diagramContainer);

      try {
        var type = mermaid.detectType(sanitizedMermaidText);
        if (!type) {
          throw new Error("Invalid diagram type");
        }
      } catch (error) {
        var errorElement = diagramContainer.find('#error-' + containerId);
        errorElement.html('<div class="alert alert-danger">' +
          '<strong>Mermaid Syntax Error:</strong><br>' +
          error.message +
          '</div>').show();
        diagramContainer.find('.diagram').hide();
      }
    });

    try {
      await mermaid.run({ querySelector: 'mermaid' });
    } catch (error) {
      console.error('Mermaid rendering error:', error);
    }

    // Trim excess whitespace from Mermaid-rendered SVGs.
    // Mermaid sometimes generates viewBoxes larger than the actual diagram content,
    // leaving empty space on the right and below. Measure real content bounds via
    // getBBox() and shrink the viewBox + max-width accordingly.
    element.find(".diagram:not(.drawio-diagram) svg").each(function() {
      var svgEl = this;
      try {
        var bbox = svgEl.getBBox();
        if (!bbox || bbox.width <= 0 || bbox.height <= 0) return;

        var padding = 8;
        var newX = Math.floor(bbox.x - padding);
        var newY = Math.floor(bbox.y - padding);
        var newW = Math.ceil(bbox.width + padding * 2);
        var newH = Math.ceil(bbox.height + padding * 2);

        svgEl.setAttribute('viewBox', newX + ' ' + newY + ' ' + newW + ' ' + newH);
        // Constrain SVG to its content width — prevents stretching to full container
        svgEl.style.maxWidth = newW + 'px';
      } catch(e) {
        // getBBox() may fail in non-browser environments — graceful fallback
      }
    });

    element.find(".diagram").each(function (index) {
      var diagram = $(this);
      if (diagram.is(':visible')) {
        var downloadButton = $('<div class="mb-3"><button class="btn btn-secondary btn-sm">Download SVG</button></div>');
        downloadButton.on('click', function () {
          var svgElement = diagram.find('svg')[0];
          if (svgElement) {
            var serializer = new XMLSerializer();
            var source = serializer.serializeToString(svgElement);
            var blob = new Blob([source], { type: 'image/svg+xml;charset=utf-8' });
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url;
            a.download = 'diagram-' + (index + 1) + '.svg';
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
          }
        });
        diagram.after(downloadButton);
      }
    });
  }

  // ── DrawIO viewer lazy loader ─────────────────────────────────────

  var drawioViewerLoaded = false;
  var drawioViewerLoading = false;
  var drawioViewerCallbacks = [];

  function ensureDrawIOViewer(callback) {
    if (drawioViewerLoaded && typeof window.GraphViewer !== 'undefined') {
      callback();
      return;
    }
    drawioViewerCallbacks.push(callback);
    if (drawioViewerLoading) return;

    drawioViewerLoading = true;

    // Suppress auto-init: viewer-static.min.js ends with an IIFE that calls
    //   if (window.onDrawioViewerLoad) window.onDrawioViewerLoad();
    //   else GraphViewer.processElements();
    // By defining onDrawioViewerLoad, we prevent the automatic processElements()
    // call so we can invoke it manually at the right time in our callback.
    window.onDrawioViewerLoad = function() {
      // intentionally empty — auto-init suppressed
    };

    function onLoadSuccess() {
      drawioViewerLoaded = true;
      drawioViewerLoading = false;
      var cbs = drawioViewerCallbacks.slice();
      drawioViewerCallbacks = [];
      cbs.forEach(function(cb) { try { cb(); } catch(e) { console.error(e); } });
    }

    function onAllFailed() {
      drawioViewerLoading = false;
      var cbs = drawioViewerCallbacks.slice();
      drawioViewerCallbacks = [];
      cbs.forEach(function(cb) { try { cb(new Error('Failed to load DrawIO viewer')); } catch(e) {} });
    }

    // Try local file first, then CDN fallback (same pattern as mermaid.min.js)
    var script = document.createElement('script');
    script.src = 'vendor/js/viewer-static.min.js';
    script.onload = onLoadSuccess;
    script.onerror = function() {
      // Fallback to CDN
      script.remove();
      var cdnScript = document.createElement('script');
      cdnScript.src = 'https://viewer.diagrams.net/js/viewer-static.min.js';
      cdnScript.onload = onLoadSuccess;
      cdnScript.onerror = onAllFailed;
      document.head.appendChild(cdnScript);
    };
    document.head.appendChild(script);
  }

  // ── DrawIO ────────────────────────────────────────────────────────

  function applyDrawIO(element) {
    var drawioElements = element.find(".drawio-code");
    if (drawioElements.length === 0) return;

    var pendingRenders = [];

    drawioElements.each(function(index) {
      var el = $(this);
      el.addClass("sourcecode");
      el.find("pre").addClass("sourcecode");

      var rawText = el.find("pre").text().trim();
      // .text() already fully unescapes HTML entities — no manual unescaping needed
      var xmlContent = rawText;

      el.find("pre").text(rawText);
      addToggleSourceCode(el, "Toggle DrawIO Diagram");

      var containerId = 'drawio-diagram-' + index + '-' + Date.now();

      // Build DOM programmatically to avoid HTML parser issues with XML in attributes
      var wrapper = document.createElement('div');
      wrapper.className = 'diagram-wrapper';

      var diagramDiv = document.createElement('div');
      diagramDiv.className = 'diagram drawio-diagram';
      diagramDiv.id = containerId;

      var mxgraphDiv = document.createElement('div');
      mxgraphDiv.className = 'mxgraph';
      // Set data-mxgraph via DOM API — bypasses HTML parser entirely
      mxgraphDiv.setAttribute('data-mxgraph', JSON.stringify({
        highlight: "#0000ff", nav: true, resize: true, xml: xmlContent
      }));

      diagramDiv.appendChild(mxgraphDiv);
      wrapper.appendChild(diagramDiv);

      var errorDiv = document.createElement('div');
      errorDiv.className = 'error-message';
      errorDiv.id = 'error-' + containerId;
      errorDiv.style.display = 'none';
      wrapper.appendChild(errorDiv);

      var diagramContainer = $(wrapper);
      el.after(diagramContainer);
      pendingRenders.push({ containerId: containerId, xmlContent: xmlContent, diagramContainer: diagramContainer });
    });

    if (pendingRenders.length === 0) return;

    ensureDrawIOViewer(function(err) {
      if (err) {
        pendingRenders.forEach(function(item) {
          item.diagramContainer.find('#error-' + item.containerId)
            .html('<div class="alert alert-danger"><strong>DrawIO Viewer Error:</strong><br>Failed to load viewer library.</div>').show();
          item.diagramContainer.find('.diagram').hide();
        });
        return;
      }

      try {
        if (window.GraphViewer && typeof GraphViewer.processElements === 'function') {
          GraphViewer.processElements();
        }
      } catch(e) { console.error('DrawIO render error:', e); }

      // Download .drawio buttons
      pendingRenders.forEach(function(item, idx) {
        var diagram = item.diagramContainer.find('.diagram');
        if (diagram.is(':visible')) {
          var btn = $('<div class="mb-3"><button class="btn btn-secondary btn-sm">Download .drawio</button></div>');
          btn.on('click', function() {
            var blob = new Blob([item.xmlContent], { type: 'application/xml;charset=utf-8' });
            var url = URL.createObjectURL(blob);
            var a = document.createElement('a');
            a.href = url; a.download = 'diagram-' + (idx + 1) + '.drawio';
            document.body.appendChild(a); a.click();
            document.body.removeChild(a); URL.revokeObjectURL(url);
          });
          diagram.after(btn);
        }
      });
    });
  }

  // ── ABC notation ───────────────────────────────────────────────────

  function abcCursorControl(element_id) {
    var self = this;

    self.onStart = function () {
      var svg = document.querySelector(element_id + ' svg');
      var cursor = document.createElementNS("http://www.w3.org/2000/svg", "line");
      cursor.setAttribute("class", "abcjs-cursor");
      cursor.setAttributeNS(null, 'x1', 0);
      cursor.setAttributeNS(null, 'y1', 0);
      cursor.setAttributeNS(null, 'x2', 0);
      cursor.setAttributeNS(null, 'y2', 0);
      svg.appendChild(cursor);
    };
    self.beatSubdivisions = 2;
    self.onEvent = function (ev) {
      if (ev.measureStart && ev.left === null) return;

      var lastSelection = document.querySelectorAll(element_id + ' svg .highlight');
      for (var k = 0; k < lastSelection.length; k++)
        lastSelection[k].classList.remove("highlight");

      for (var i = 0; i < ev.elements.length; i++) {
        var note = ev.elements[i];
        for (var j = 0; j < note.length; j++) {
          note[j].classList.add("highlight");
        }
      }

      var cursor = document.querySelector(element_id + ' svg .abcjs-cursor');
      if (cursor) {
        cursor.setAttribute("x1", ev.left - 2);
        cursor.setAttribute("x2", ev.left - 2);
        cursor.setAttribute("y1", ev.top);
        cursor.setAttribute("y2", ev.top + ev.height);
      }
    };
    self.onFinished = function () {
      var els = document.querySelectorAll("svg .highlight");
      for (var i = 0; i < els.length; i++) {
        els[i].classList.remove("highlight");
      }
      var cursor = document.querySelector(element_id + ' svg .abcjs-cursor');
      if (cursor) {
        cursor.setAttribute("x1", 0);
        cursor.setAttribute("x2", 0);
        cursor.setAttribute("y1", 0);
        cursor.setAttribute("y2", 0);
      }
    };
  }

  function abcClickListener(abcElem, tuneNumber, classes, analysis, drag, mouseEvent) {
    var lastClicked = abcElem.midiPitches;
    if (!lastClicked) return;
    ABCJS.synth.playEvent(lastClicked, abcElem.midiGraceNotePitches);
  }

  async function applyAbc(element) {
    // Lazy-load ABCjs on first use
    if (window.LazyLoader) await window.LazyLoader.abcjs();
    if (typeof ABCJS === 'undefined') return;
    element.find(".abc-code").each(function () {
      $(this).addClass("sourcecode");
      $(this).find("pre").addClass("sourcecode");
      var abcElement = $(this);
      var abcId = '' + Date.now() + '-' + Math.random().toString(36).substr(2, 6);
      var abcText = abcElement.find("pre").text().trim();
      abcText = abcText.split("\n").map(function(line) { return line.trim(); }).join("\n");

      var instrument = "";
      var instrumentMatch = abcText.match(/^%%tablature\s+(.*)/);
      if (instrumentMatch) {
        instrument = instrumentMatch[1];
      }

      abcElement.find("pre").text(abcText);
      var abcSVG = 'abc-svg-' + abcId;
      var abcMidi = 'abc-midi-' + abcId;
      addToggleSourceCode(abcElement, "Toggle ABC Notation");

      // Create DOM elements directly (avoids ABCJS ID lookup timing issues)
      var svgDiv = document.createElement('div');
      svgDiv.id = abcSVG;
      svgDiv.className = 'abc-svg';
      var midiDiv = document.createElement('div');
      midiDiv.id = abcMidi;
      midiDiv.className = 'abc-midi';
      abcElement.after(midiDiv);
      abcElement.after(svgDiv);

      var abcOptions = {
        add_classes: true,
        clickListener: self.abcClickListener,
        responsive: "resize",
        soundfont: "https://paulrosen.github.io/midi-js-soundfonts/FluidR3_GM/",
        scale: 0.65,
        staffwidth: 740,
        paddingtop: 6,
        paddingbottom: 2,
        format: {
          titlefont: '"itim-music,Itim" 11',
          gchordfont: '"itim-music,Itim" 9',
          vocalfont: '"itim-music,Itim" 9',
          annotationfont: '"itim-music,Itim" 9',
          composerfont: '"itim-music,Itim" 9',
          partsfont: '"itim-music,Itim" 9',
          tempoFont: '"itim-music,Itim" 9',
          wordsfont: '"itim-music,Itim" 9',
          infofont: '"itim-music,Itim" 9',
          tablabelfont: "Helvetica 9 box",
          tabnumberfont: "Times 9",
          dynamicVAlign: false,
          dynamicHAlign: false
        }
      };
      if (instrument === "violin" || instrument === "mandolin" || instrument === "fiddle" || instrument === "guitar" || instrument === "fiveString") {
        abcOptions.tablature = [{ instrument: instrument }];
      } else if (instrument === "bass") {
        abcOptions.tablature = [{ instrument: "bass", label: "Base (%T)", tuning: ["E,", "A,", "D", "G"] }];
      }

      // Pass DOM element directly to renderAbc for reliable rendering
      var renderResult = ABCJS.renderAbc(svgDiv, abcText, abcOptions);
      if (!renderResult || renderResult.length === 0) {
        console.error('[applyAbc] ABCJS.renderAbc returned empty result for:', abcText.substring(0, 100));
      }
      var visualObj = renderResult ? renderResult[0] : null;

      // Trim excess bottom whitespace from the viewBox set by ABCJS responsive mode.
      // ABCJS responsive:"resize" creates a viewBox that is often taller than the
      // actual notation content, producing a visible gap before the MIDI player.
      // We measure the real content bounds via child <g> getBBox() and shrink the
      // viewBox height accordingly.
      var svgEl = svgDiv.querySelector('svg');
      if (svgEl) {
        var vb = svgEl.getAttribute('viewBox');
        if (vb) {
          var parts = vb.split(/[\s,]+/).map(Number);
          if (parts.length === 4) {
            var maxBottom = 0;
            var children = svgEl.children;
            for (var ci = 0; ci < children.length; ci++) {
              if (children[ci].tagName === 'g') {
                try {
                  var gb = children[ci].getBBox();
                  var bottom = gb.y + gb.height;
                  if (bottom > maxBottom) maxBottom = bottom;
                } catch(e) { /* getBBox may fail on hidden elements */ }
              }
            }
            // Only trim if we found content and it's meaningfully shorter than viewBox
            if (maxBottom > 0 && maxBottom + 8 < parts[3]) {
              svgEl.setAttribute('viewBox', parts[0] + ' ' + parts[1] + ' ' + parts[2] + ' ' + (maxBottom + 8));
            }
          }
        }
      }

      // Always set up ABCJS MIDI synth for playback
      if (visualObj && ABCJS.synth.supportsAudio()) {
        var synthControl = new ABCJS.synth.SynthController();
        var cursorControl = new abcCursorControl('#' + abcSVG);
        synthControl.load('#' + abcMidi, cursorControl, {
          displayLoop: true,
          displayRestart: true,
          displayPlay: true,
          displayProgress: true,
          displayWarp: true
        });

        // Force compact sizing on ABCJS audio controls via inline styles.
        // This bypasses CSS cascade/layer issues that can leave controls oversized.
        var audioEl = midiDiv.querySelector('.abcjs-inline-audio');
        if (audioEl) {
          audioEl.style.height = '26px';
          audioEl.style.padding = '0 5px';
          audioEl.style.boxSizing = 'border-box';
          var btns = midiDiv.querySelectorAll('.abcjs-btn');
          for (var b = 0; b < btns.length; b++) {
            btns[b].style.width = '28px';
            btns[b].style.height = '26px';
            btns[b].style.padding = '4px';
            btns[b].style.boxSizing = 'border-box';
          }
          var svgs = midiDiv.querySelectorAll('.abcjs-btn svg');
          for (var s = 0; s < svgs.length; s++) {
            svgs[s].style.width = '100%';
            svgs[s].style.height = '100%';
          }
          var progBg = midiDiv.querySelector('.abcjs-midi-progress-background');
          if (progBg) {
            progBg.style.height = '10px';
          }
          var clock = midiDiv.querySelector('.abcjs-midi-clock');
          if (clock) {
            clock.style.fontSize = '16px';
          }
          var tempoWrap = midiDiv.querySelector('.abcjs-tempo-wrapper');
          if (tempoWrap) {
            tempoWrap.style.fontSize = '10px';
          }
        }

        synthControl.setTune(visualObj, false, {});
      } else if (!visualObj) {
        midiDiv.innerHTML = "<div class='audio-error'>Failed to parse ABC notation.</div>";
      } else {
        midiDiv.innerHTML = "<div class='audio-error'>Audio is not supported in this browser.</div>";
      }
    });
  }

  // ── Toggle / source code helpers ───────────────────────────────────

  function applyToggle(element, nl2br) {
    if (element.find(".sourcecode-toggle").length > 0) {
      return;
    }
    element.find(".toggle").each(function () {
      var toggleElement = $(this);
      toggleElement.addClass("sourcecode");
      toggleElement.find("pre").addClass("sourcecode");

      if (nl2br) {
        var toggleText = toggleElement.text().trim().replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>").replace(/\s/g, "&nbsp;");
        toggleElement.find("pre").text(toggleText);
      }
      addToggleSourceCode(toggleElement, toggleElement.data("label"));
    });
  }

  function addToggleSourceCode(element, title) {
    title = title || "Toggle Show/Hide";
    if (element.data("title")) {
      title = element.data("title");
    }
    var toggleHide = "<i class='fa-solid fa-toggle-on'></i> " + title;
    var toggleShow = "<i class='fa-solid fa-toggle-off'></i> " + title;
    var controlDiv = '<div class="sourcecode-toggle unselectable">' + toggleShow + '</div>';
    element.before(controlDiv);
    element.prev().click(function () {
      var sourcecode = $(this).next();
      sourcecode.toggle();
      if (sourcecode.is(":visible")) {
        $(this).html(toggleHide);
      } else {
        $(this).html(toggleShow);
      }
    });
    element.hide();
  }

  function formatSourceCode(element) {
    element.find(".sourcecode").each(function () {
      var sourceCodeElement = $(this);
      var sourceCode = sourceCodeElement.text().trim();
      sourceCodeElement.find("code").text(sourceCode);
    });
  }

  function cleanupListCodeBlocks(element) {
    element.find('li').each(function() {
      var $li = $(this);
      var children = $li.contents();

      children.each(function(index) {
        if (this.nodeType === Node.TEXT_NODE) {
          var text = $(this).text().trim();
          if (text.match(/^[0-9]{1,2}$/)) {
            var prevSibling = $(this).prev();
            if (prevSibling.hasClass('highlight') || prevSibling.find('.highlight').length > 0) {
              $(this).remove();
            }
          }
        }
      });
    });
  }

  // ── isElementInViewport ────────────────────────────────────────────

  function isElementInViewport(element) {
    var rect = element.getBoundingClientRect();
    return (
      rect.top >= 0 &&
      rect.left >= 0 &&
      rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
      rect.right <= (window.innerWidth || document.documentElement.clientWidth)
    );
  }

  // ── Namespace export ───────────────────────────────────────────────
  var ns = {
    getMessageAppName: getMessageAppName,
    getMessageMonadicFlag: getMessageMonadicFlag,
    renderMessage: renderMessage,
    setCopyCodeButton: setCopyCodeButton,
    applyMathJax: applyMathJax,
    mermaid_config: mermaid_config,
    sanitizeMermaidSource: sanitizeMermaidSource,
    applyMermaid: applyMermaid,
    abcCursorControl: abcCursorControl,
    abcClickListener: abcClickListener,
    applyAbc: applyAbc,
    applyDrawIO: applyDrawIO,
    applyToggle: applyToggle,
    addToggleSourceCode: addToggleSourceCode,
    formatSourceCode: formatSourceCode,
    cleanupListCodeBlocks: cleanupListCodeBlocks,
    isElementInViewport: isElementInViewport
  };

  window.WsContentRenderer = ns;

  // Backward-compat individual exports
  window.applyMathJax = applyMathJax;
  window.applyMermaid = applyMermaid;
  window.applyDrawIO = applyDrawIO;
  window.applyAbc = applyAbc;
  window.applyToggle = applyToggle;
  window.addToggleSourceCode = addToggleSourceCode;
  window.formatSourceCode = formatSourceCode;
  window.cleanupListCodeBlocks = cleanupListCodeBlocks;
  window.setCopyCodeButton = setCopyCodeButton;
  window.renderMessage = renderMessage;
  window.isElementInViewport = isElementInViewport;

  // Support for Jest testing environment (CommonJS)
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = ns;
  }
})();
