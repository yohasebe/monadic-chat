// Mask editor for image generation applications
// This is used for creating mask images for OpenAI's image edit API

// NOTE: currentMaskData is defined in select_image.js, so we don't define it here

// Open mask editor for the selected image
function openMaskEditor(imageData) {
  // Create modal dialog
  var modalHTML = `
    <div class="modal fade" id="maskEditorModal" tabindex="-1" role="dialog" aria-hidden="true">
      <div class="modal-dialog modal-lg">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">
              <i class="fas fa-brush"></i> Create Mask
              <small class="text-muted ml-2">Draw on areas you want AI to edit</small>
            </h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body">
            <div class="row">
              <div class="col-md-8">
                <div class="canvas-container" style="position: relative;">
                  <canvas id="maskCanvas" style="border: 1px solid #ddd;"></canvas>
                </div>
              </div>
              <div class="col-md-4">
                <div class="form-group mb-3">
                  <label for="brushSize">Brush Size: <span id="brushSizeValue">20px</span></label>
                  <input type="range" id="brushSize" min="1" max="50" value="20" class="form-control">
                </div>
                <div class="btn-group mb-3 w-100" role="group">
                  <button id="brushTool" class="btn btn-primary active">
                    <i class="fas fa-paint-brush"></i> Brush
                  </button>
                  <button id="eraserTool" class="btn btn-secondary">
                    <i class="fas fa-eraser"></i> Eraser
                  </button>
                </div>
                <div class="btn-group mb-3 w-100" role="group">
                  <button id="undoMask" class="btn btn-outline-secondary w-50">
                    <i class="fas fa-undo"></i> Undo
                  </button>
                  <button id="clearMask" class="btn btn-danger w-50">
                    <i class="fas fa-trash"></i> Clear
                  </button>
                </div>
                <div class="alert alert-info">
                  <p><i class="fas fa-info-circle"></i> Draw on areas you want AI to edit. White areas will be replaced by AI. Black areas will be preserved.
                </div>
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
            <button type="button" class="btn btn-primary" id="saveMask">
              <i class="fas fa-save"></i> Save Mask
            </button>
          </div>
        </div>
      </div>
    </div>
  `;

  document.body.insertAdjacentHTML('beforeend', modalHTML);
  var maskModalEl = document.getElementById('maskEditorModal');
  bootstrap.Modal.getOrCreateInstance(maskModalEl).show();

  // Initialize canvas
  const canvas = document.getElementById("maskCanvas");
  const ctx = canvas.getContext("2d");
  let isDrawing = false;
  let tool = "brush"; // brush or eraser

  // Stroke-based undo state
  let strokes = [];       // [{tool, points: [{x,y}], brushSize}]
  let currentStroke = [];
  let currentBrushSize = 0;

  // Update brush size display
  var brushSizeInput = document.getElementById('brushSize');
  if (brushSizeInput) {
    brushSizeInput.addEventListener('input', function() {
      var sizeLabel = document.getElementById('brushSizeValue');
      if (sizeLabel) sizeLabel.textContent = this.value + 'px';
    });
  }

  // Load image and set canvas size
  const img = new Image();
  img.onload = function() {
    // Calculate display size (maintain aspect ratio and fit in modal)
    var colEl = document.querySelector(".modal-body .col-md-8");
    const maxWidth = (colEl ? colEl.clientWidth : 600) - 20;
    const maxHeight = window.innerHeight * 0.6;

    let width = img.width;
    let height = img.height;

    if (width > maxWidth) {
      const ratio = maxWidth / width;
      width = maxWidth;
      height = height * ratio;
    }

    if (height > maxHeight) {
      const ratio = maxHeight / height;
      height = height * ratio;
      width = width * ratio;
    }

    // Set canvas display size
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    // Set canvas actual size (same as original image for mask output quality)
    canvas.width = img.width;
    canvas.height = img.height;

    drawBase();
  };
  img.src = imageData.data;

  // --- Drawing helpers ---

  function drawBase() {
    ctx.fillStyle = "black";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.globalAlpha = 0.6;
    ctx.drawImage(img, 0, 0);
    ctx.globalAlpha = 1.0;
  }

  function getCanvasCoords(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left) * (canvas.width / rect.width),
      y: (clientY - rect.top) * (canvas.height / rect.height)
    };
  }

  function scaledBrushSize() {
    const rect = canvas.getBoundingClientRect();
    var sizeInput = document.getElementById('brushSize');
    return parseInt(sizeInput ? sizeInput.value : '20') * (canvas.width / rect.width);
  }

  function drawDot(x, y, brushSize, useTool) {
    if (useTool === "brush") {
      ctx.beginPath();
      ctx.arc(x, y, brushSize, 0, Math.PI * 2);
      ctx.fillStyle = "white";
      ctx.fill();
    } else {
      eraseCircle(x, y, brushSize);
    }
  }

  // Helper function to erase a circle cleanly
  function eraseCircle(x, y, radius) {
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fillStyle = "black";
    ctx.fill();

    const currentAlpha = ctx.globalAlpha;
    ctx.globalAlpha = 0.6;
    ctx.save();
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.clip();
    ctx.drawImage(img, 0, 0);
    ctx.restore();
    ctx.globalAlpha = currentAlpha;
  }

  function replayStrokes() {
    for (const stroke of strokes) {
      for (const pt of stroke.points) {
        drawDot(pt.x, pt.y, stroke.brushSize, stroke.tool);
      }
    }
  }

  function redrawAll() {
    drawBase();
    replayStrokes();
  }

  function endStroke() {
    if (!isDrawing) return;
    isDrawing = false;
    if (currentStroke.length > 0) {
      strokes.push({
        tool: tool,
        points: currentStroke,
        brushSize: currentBrushSize
      });
      currentStroke = [];
    }
  }

  // Drawing tool event handlers
  var brushToolBtn = document.getElementById('brushTool');
  var eraserToolBtn = document.getElementById('eraserTool');

  if (brushToolBtn) {
    brushToolBtn.addEventListener('click', function() {
      tool = "brush";
      this.classList.add("active");
      if (eraserToolBtn) eraserToolBtn.classList.remove("active");
    });
  }

  if (eraserToolBtn) {
    eraserToolBtn.addEventListener('click', function() {
      tool = "eraser";
      this.classList.add("active");
      if (brushToolBtn) brushToolBtn.classList.remove("active");
    });
  }

  // Undo last stroke
  var undoBtn = document.getElementById('undoMask');
  if (undoBtn) {
    undoBtn.addEventListener('click', function() {
      if (strokes.length > 0) {
        strokes.pop();
        redrawAll();
      }
    });
  }

  // Clear all strokes
  var clearBtn = document.getElementById('clearMask');
  if (clearBtn) {
    clearBtn.addEventListener('click', function() {
      strokes = [];
      drawBase();
    });
  }

  // --- Mouse event handlers ---
  canvas.addEventListener("mousedown", function(e) {
    isDrawing = true;
    const pt = getCanvasCoords(e.clientX, e.clientY);
    currentBrushSize = scaledBrushSize();
    currentStroke = [pt];
    drawDot(pt.x, pt.y, currentBrushSize, tool);
  });

  canvas.addEventListener("mousemove", function(e) {
    if (!isDrawing) return;
    const pt = getCanvasCoords(e.clientX, e.clientY);
    currentStroke.push(pt);
    drawDot(pt.x, pt.y, currentBrushSize, tool);
  });

  canvas.addEventListener("mouseup", endStroke);
  canvas.addEventListener("mouseout", endStroke);

  // --- Touch event handlers (direct coordinate extraction, passive: false) ---
  canvas.addEventListener("touchstart", function(e) {
    e.preventDefault();
    const touch = e.touches[0];
    const pt = getCanvasCoords(touch.clientX, touch.clientY);
    isDrawing = true;
    currentBrushSize = scaledBrushSize();
    currentStroke = [pt];
    drawDot(pt.x, pt.y, currentBrushSize, tool);
  }, {passive: false});

  canvas.addEventListener("touchmove", function(e) {
    if (!isDrawing) return;
    e.preventDefault();
    const touch = e.touches[0];
    const pt = getCanvasCoords(touch.clientX, touch.clientY);
    currentStroke.push(pt);
    drawDot(pt.x, pt.y, currentBrushSize, tool);
  }, {passive: false});

  canvas.addEventListener("touchend", endStroke);

  // Save mask
  var saveBtn = document.getElementById('saveMask');
  if (saveBtn) {
    saveBtn.addEventListener('click', function() {
    try {
      // Create a clean copy of the mask (without the semi-transparent image)
      const tempCanvas = document.createElement("canvas");
      tempCanvas.width = canvas.width;
      tempCanvas.height = canvas.height;
      const tempCtx = tempCanvas.getContext("2d");

      // Copy only the mask
      tempCtx.drawImage(canvas, 0, 0);

      // Create mask data with a clearer naming convention that identifies it as a mask
      const maskFilename = `mask__${imageData.title}`;

      // Create mask with proper alpha channel as required by OpenAI
      const imgData = tempCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
      const data = imgData.data;

      // Convert black pixels to white with full opacity, white pixels to transparent
      for (let i = 0; i < data.length; i += 4) {
        if (data[i] > 200 && data[i+1] > 200 && data[i+2] > 200) {
          data[i+3] = 0;
        } else {
          data[i] = 255;
          data[i+1] = 255;
          data[i+2] = 255;
          data[i+3] = 255;
        }
      }

      // Create a separate visible mask image for the UI display
      const visibleMaskCanvas = document.createElement("canvas");
      visibleMaskCanvas.width = canvas.width;
      visibleMaskCanvas.height = canvas.height;
      const visibleMaskCtx = visibleMaskCanvas.getContext("2d");

      visibleMaskCtx.fillStyle = "white";
      visibleMaskCtx.fillRect(0, 0, visibleMaskCanvas.width, visibleMaskCanvas.height);

      const originalImgData = tempCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
      const originalData = originalImgData.data;
      const visibleMaskImgData = visibleMaskCtx.getImageData(0, 0, visibleMaskCanvas.width, visibleMaskCanvas.height);
      const visibleMaskData = visibleMaskImgData.data;

      for (let i = 0; i < originalData.length; i += 4) {
        if (originalData[i] > 200 && originalData[i+1] > 200 && originalData[i+2] > 200) {
          visibleMaskData[i] = 0;
          visibleMaskData[i+1] = 0;
          visibleMaskData[i+2] = 0;
          visibleMaskData[i+3] = 255;
        }
      }

      visibleMaskCtx.putImageData(visibleMaskImgData, 0, 0);
      tempCtx.putImageData(imgData, 0, 0);

      window.currentMaskData = {
        title: maskFilename,
        data: tempCanvas.toDataURL("image/png"),
        display_data: visibleMaskCanvas.toDataURL("image/png"),
        type: "image/png",
        for_image: imageData.title,
        is_mask: true,
        mask_for: imageData.title
      };

      images.push(window.currentMaskData);

      const maskCreatedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.maskCreated') : 'Mask created for';
      setAlert(`<i class='fa-solid fa-circle-check'></i> ${maskCreatedMsg} ${imageData.title}`, "success");

      const existingImageIndex = images.findIndex(img =>
        img.title === imageData.title && img !== window.currentMaskData
      );

      var imageUsedEl = document.getElementById('image-used');

      if (existingImageIndex !== -1) {
        if (imageUsedEl) {
          imageUsedEl.insertAdjacentHTML('beforeend', `
            <div class="mask-overlay-container" data-original-image="${imageData.title}">
              <img class='base-image' alt='${imageData.title}' src='${imageData.data}' />
              <img class='mask-overlay' alt='${maskFilename}' src='${window.currentMaskData.display_data || window.currentMaskData.data}' />
              <div class="mask-overlay-label">MASK</div>
              <div class="mask-controls">
                <button class='btn btn-sm btn-danger remove-mask' data-mask-filename='${maskFilename}' tabindex="99">
                  <i class="fas fa-times"></i> Remove Mask
                </button>
                <button class='btn btn-sm btn-secondary toggle-mask' tabindex="100">
                  <i class="fas fa-eye-slash"></i> Toggle Mask
                </button>
              </div>
            </div>
          `);
        }

        // Hide original image container
        var origImg = document.querySelector(`.image-container img[alt="${imageData.title}"]`);
        if (origImg) {
          var container = origImg.closest('.image-container');
          if (container) container.style.display = 'none';
        }
      } else {
        if (imageUsedEl) {
          imageUsedEl.insertAdjacentHTML('beforeend', `
            <div class="mask-overlay-container" data-original-image="${imageData.title}">
              <img class='base-image' alt='${imageData.title}' src='${imageData.data}' />
              <img class='mask-overlay' alt='${maskFilename}' src='${window.currentMaskData.display_data || window.currentMaskData.data}' />
              <div class="mask-overlay-label">MASK</div>
              <div class="mask-controls">
                <button class='btn btn-sm btn-danger remove-mask' data-mask-filename='${maskFilename}' tabindex="99">
                  <i class="fas fa-times"></i> Remove Mask
                </button>
                <button class='btn btn-sm btn-secondary toggle-mask' tabindex="100">
                  <i class="fas fa-eye-slash"></i> Toggle Mask
                </button>
              </div>
            </div>
          `);
        }
      }

      // Handle mask removal (use event delegation)
      document.querySelectorAll('.remove-mask').forEach(function(btn) {
        btn.onclick = function() {
          var mfn = this.dataset.maskFilename;
          var overlayContainer = this.closest('.mask-overlay-container');
          var originalImageTitle = overlayContainer ? overlayContainer.dataset.originalImage : null;

          var indexToRemove = images.findIndex(function(img) { return img.title === mfn; });
          if (indexToRemove !== -1) {
            images.splice(indexToRemove, 1);
          }

          window.currentMaskData = null;

          if (overlayContainer) overlayContainer.remove();

          // Show the original image if it exists
          if (originalImageTitle) {
            var hiddenImg = document.querySelector(`.image-container img[alt="${originalImageTitle}"]`);
            if (hiddenImg) {
              var hiddenContainer = hiddenImg.closest('.image-container');
              if (hiddenContainer && hiddenContainer.style.display === 'none') {
                hiddenContainer.style.display = '';
              }
            }
          }

          updateFileDisplay(images);

          var maskRemovedMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.maskRemoved') : 'Mask removed';
          setAlert(`<i class='fa-solid fa-circle-check'></i> ${maskRemovedMsg}`, "success");
        };
      });

      // Handle mask toggle
      document.querySelectorAll('.toggle-mask').forEach(function(btn) {
        btn.onclick = function() {
          var overlayContainer = this.closest('.mask-overlay-container');
          var maskOverlay = overlayContainer ? overlayContainer.querySelector('.mask-overlay') : null;
          var icon = this.querySelector('i');

          if (maskOverlay) {
            var currentOpacity = window.getComputedStyle(maskOverlay).opacity;
            if (currentOpacity === "0") {
              maskOverlay.style.opacity = "0.6";
              if (icon) { icon.classList.remove("fa-eye"); icon.classList.add("fa-eye-slash"); }
            } else {
              maskOverlay.style.opacity = "0";
              if (icon) { icon.classList.remove("fa-eye-slash"); icon.classList.add("fa-eye"); }
            }
          }
        };
      });

      // Close modal
      bootstrap.Modal.getOrCreateInstance(maskModalEl).hide();
      setTimeout(function() {
        var modalToRemove = document.getElementById('maskEditorModal');
        if (modalToRemove) modalToRemove.remove();
      }, 500);
    } catch (error) {
      console.error("Error saving mask:", error);
      setAlert("Error creating mask: " + error.message, "error");
    }
    });
  }

  // Cleanup when modal is closed
  if (maskModalEl) {
    maskModalEl.addEventListener('hidden.bs.modal', function() {
      this.remove();
    });
  }
}

// Export functions to window for browser environment
window.openMaskEditor = openMaskEditor;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    openMaskEditor
  };
}
