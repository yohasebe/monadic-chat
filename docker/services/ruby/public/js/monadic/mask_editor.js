// Mask editor for image generation applications
// This is used for creating mask images for OpenAI's image edit API

// NOTE: currentMaskData is defined in select_image.js, so we don't define it here

// Open mask editor for the selected image
function openMaskEditor(imageData) {
  // Create modal dialog
  const modal = $(`
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
                <div class="form-group">
                  <label for="brushSize">Brush Size:</label>
                  <input type="range" id="brushSize" min="1" max="50" value="20" class="form-control">
                  <span id="brushSizeValue">20px</span>
                </div>
                <div class="btn-group mb-3 w-100" role="group">
                  <button id="brushTool" class="btn btn-primary active">
                    <i class="fas fa-paint-brush"></i> Brush
                  </button>
                  <button id="eraserTool" class="btn btn-secondary">
                    <i class="fas fa-eraser"></i> Eraser
                  </button>
                </div>
                <button id="clearMask" class="btn btn-danger w-100 mb-3">
                  <i class="fas fa-trash"></i> Clear Mask
                </button>
                <div class="alert alert-info">
                  <i class="fas fa-info-circle"></i> Draw on areas you want AI to edit.
                  <ul class="mb-0 mt-2">
                    <li>White areas = Will be replaced by AI</li>
                    <li>Black areas = Will be preserved</li>
                  </ul>
                  <small class="text-muted">The mask will be converted to have proper alpha channel required by OpenAI.</small>
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
  `);
  
  $("body").append(modal);
  $("#maskEditorModal").modal("show");
  
  // Initialize canvas 
  const canvas = document.getElementById("maskCanvas");
  const ctx = canvas.getContext("2d");
  let isDrawing = false;
  let tool = "brush"; // brush or eraser
  
  // Update brush size display
  $("#brushSize").on("input", function() {
    $("#brushSizeValue").text(`${$(this).val()}px`);
  });
  
  // Load image and set canvas size
  const img = new Image();
  img.onload = function() {
    // Calculate display size (maintain aspect ratio and fit in modal)
    const maxWidth = $(".modal-body .col-md-8").width() - 20;
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
    
    // Set canvas actual size (same as original image)
    canvas.width = img.width;
    canvas.height = img.height;
    
    // Initialize background as black (preserved area)
    ctx.fillStyle = "black";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    
    // Show original image as a semi-transparent background
    ctx.globalAlpha = 0.3;
    ctx.drawImage(img, 0, 0);
    ctx.globalAlpha = 1.0;
  };
  img.src = imageData.data;
  
  // Drawing tool event handlers
  $("#brushTool").on("click", function() {
    tool = "brush";
    $(this).addClass("active");
    $("#eraserTool").removeClass("active");
  });
  
  $("#eraserTool").on("click", function() {
    tool = "eraser";
    $(this).addClass("active");
    $("#brushTool").removeClass("active");
  });
  
  $("#clearMask").on("click", function() {
    ctx.fillStyle = "black";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.globalAlpha = 0.3;
    ctx.drawImage(img, 0, 0);
    ctx.globalAlpha = 1.0;
  });
  
  // Drawing event handlers
  canvas.addEventListener("mousedown", startDrawing);
  canvas.addEventListener("mousemove", draw);
  canvas.addEventListener("mouseup", stopDrawing);
  canvas.addEventListener("mouseout", stopDrawing);
  
  // Touch screen support
  canvas.addEventListener("touchstart", handleTouch);
  canvas.addEventListener("touchmove", handleTouch);
  canvas.addEventListener("touchend", stopDrawing);
  
  function handleTouch(e) {
    e.preventDefault();
    const touch = e.touches[0];
    const mouseEvent = new MouseEvent(e.type === "touchstart" ? "mousedown" : "mousemove", {
      clientX: touch.clientX,
      clientY: touch.clientY
    });
    canvas.dispatchEvent(mouseEvent);
  }
  
  function startDrawing(e) {
    isDrawing = true;
    draw(e);
  }
  
  function draw(e) {
    if (!isDrawing) return;
    
    // Calculate position, accounting for canvas scaling
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    
    const x = (e.clientX - rect.left) * scaleX;
    const y = (e.clientY - rect.top) * scaleY;
    const brushSize = parseInt($("#brushSize").val());
    
    // Draw circle at cursor position
    ctx.beginPath();
    ctx.arc(x, y, brushSize, 0, Math.PI * 2);
    ctx.fillStyle = tool === "brush" ? "white" : "black";
    ctx.fill();
  }
  
  function stopDrawing() {
    isDrawing = false;
  }
  
  // Save mask
  $("#saveMask").on("click", function() {
    try {
      // Create a clean copy of the mask (without the semi-transparent image)
      const tempCanvas = document.createElement("canvas");
      tempCanvas.width = canvas.width;
      tempCanvas.height = canvas.height;
      const tempCtx = tempCanvas.getContext("2d");
      
      // Copy only the mask
      tempCtx.drawImage(canvas, 0, 0);
      
      // Create mask data with a clearer naming convention that identifies it as a mask
      // Use a prefix that clearly identifies this as a mask image
      // Using plain "mask__" prefix to ensure the name is clearly identifiable as a mask
      const maskFilename = `mask__${imageData.title}`;
      
      // Create mask with proper alpha channel as required by OpenAI
      // The transparent areas will be edited, filled areas preserved
      const imgData = tempCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
      const data = imgData.data;
      
      // Convert black pixels to white with full opacity, white pixels to transparent
      // This follows OpenAI's requirement: transparent areas = edited, filled areas = preserved
      for (let i = 0; i < data.length; i += 4) {
        // If pixel is white or light (drawn area to be edited)
        if (data[i] > 200 && data[i+1] > 200 && data[i+2] > 200) {
          // Make it transparent (area to be edited)
          data[i+3] = 0; // Set alpha to 0 (fully transparent)
        } else {
          // Make non-white pixels white with full opacity (area to be preserved)
          data[i] = 255;   // R
          data[i+1] = 255; // G
          data[i+2] = 255; // B
          data[i+3] = 255; // A (fully opaque)
        }
      }
      
      // Create a separate visible mask image for the UI display
      // This makes the mask clearly visible with the drawn areas in black
      const visibleMaskCanvas = document.createElement("canvas");
      visibleMaskCanvas.width = canvas.width;
      visibleMaskCanvas.height = canvas.height;
      const visibleMaskCtx = visibleMaskCanvas.getContext("2d");
      
      // Set background to white
      visibleMaskCtx.fillStyle = "white";
      visibleMaskCtx.fillRect(0, 0, visibleMaskCanvas.width, visibleMaskCanvas.height);
      
      // Draw the original mask (before transparency conversion) in black
      const originalImgData = tempCtx.getImageData(0, 0, tempCanvas.width, tempCanvas.height);
      const originalData = originalImgData.data;
      const visibleMaskImgData = visibleMaskCtx.getImageData(0, 0, visibleMaskCanvas.width, visibleMaskCanvas.height);
      const visibleMaskData = visibleMaskImgData.data;
      
      // Convert white pixels to black for visibility
      for (let i = 0; i < originalData.length; i += 4) {
        // If pixel was white in original (drawn areas)
        if (originalData[i] > 200 && originalData[i+1] > 200 && originalData[i+2] > 200) {
          // Make it black in the visible mask
          visibleMaskData[i] = 0;     // R
          visibleMaskData[i+1] = 0;   // G
          visibleMaskData[i+2] = 0;   // B
          visibleMaskData[i+3] = 255; // A (fully opaque)
        }
      }
      
      // Put the visible mask data back on the canvas
      visibleMaskCtx.putImageData(visibleMaskImgData, 0, 0);
      
      // Put the modified image data back on the canvas
      tempCtx.putImageData(imgData, 0, 0);
      
      // Use the global currentMaskData from select_image.js
      window.currentMaskData = {
        title: maskFilename,
        data: tempCanvas.toDataURL("image/png"), // The OpenAI-compatible mask with transparency
        display_data: visibleMaskCanvas.toDataURL("image/png"), // The visible black mask for UI display
        type: "image/png",
        for_image: imageData.title,
        is_mask: true, // Add a flag to identify this as a mask
        mask_for: imageData.title // Reference to the original image
      };
      
      console.log("Saving mask image...");
      
      // Add mask to images array so it gets sent with the message
      // This ensures it's saved to the shared folder like other images
      images.push(window.currentMaskData);
      console.log("Mask added to images:", maskFilename);
      
      // Show success alert
      setAlert(`<i class='fa-solid fa-circle-check'></i> Mask created for ${imageData.title}`, "success");
      
      // Find if the image is already in the display
      const existingImageIndex = images.findIndex(img => 
        img.title === imageData.title && img !== window.currentMaskData
      );
      
      // If the original image exists separately from the mask, use that
      if (existingImageIndex !== -1) {
        // Create mask overlay container on top of the existing image
        $("#image-used").append(`
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
        
        // Remove original image from display (it's now part of the overlay)
        $(`.image-container:has(img[alt="${imageData.title}"])`).hide();
      } else {
        // Create mask overlay container with the base image
        $("#image-used").append(`
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
      
      // Handle mask removal
      $(".remove-mask").on("click", function() {
        // Get the mask filename from the data attribute
        const maskFilename = $(this).data("mask-filename");
        const originalImageTitle = $(this).closest(".mask-overlay-container").data("original-image");
        
        // Remove mask from images array
        const indexToRemove = images.findIndex(img => img.title === maskFilename);
        if (indexToRemove !== -1) {
          images.splice(indexToRemove, 1);
          console.log("Mask removed from images array:", maskFilename);
        }
        
        // Clear global mask data
        window.currentMaskData = null;
        
        // Remove the mask overlay container
        $(this).closest(".mask-overlay-container").remove();
        
        // Show the original image if it exists
        $(`.image-container:has(img[alt="${originalImageTitle}"]):hidden`).fadeIn();
        
        // Update the display to ensure everything is shown correctly
        updateFileDisplay(images);
        
        // Show success alert
        setAlert(`<i class='fa-solid fa-circle-check'></i> Mask removed`, "success");
      });
      
      // Handle mask toggle
      $(".toggle-mask").on("click", function() {
        const $maskOverlay = $(this).closest(".mask-overlay-container").find(".mask-overlay");
        const $icon = $(this).find("i");
        
        if ($maskOverlay.css("opacity") === "0") {
          // Show mask
          $maskOverlay.css("opacity", "0.6");
          $icon.removeClass("fa-eye").addClass("fa-eye-slash");
        } else {
          // Hide mask
          $maskOverlay.css("opacity", "0");
          $icon.removeClass("fa-eye-slash").addClass("fa-eye");
        }
      });
      
      // Close modal
      $("#maskEditorModal").modal("hide");
      setTimeout(() => {
        $("#maskEditorModal").remove();
      }, 500);
    } catch (error) {
      console.error("Error saving mask:", error);
      setAlert("Error creating mask: " + error.message, "error");
    }
  });
  
  // Cleanup when modal is closed
  $("#maskEditorModal").on("hidden.bs.modal", function() {
    $(this).remove();
  });
}

// Export functions to window for browser environment
window.openMaskEditor = openMaskEditor;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    openMaskEditor
  };
}