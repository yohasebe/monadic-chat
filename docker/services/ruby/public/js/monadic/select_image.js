//////////////////////////////
// Read image/PDF/document file contents
//////////////////////////////

// PDF support depends on model capability (supports_pdf_upload in model_spec)
// File Inputs support depends on model capability (supports_file_inputs in model_spec)

const MAX_PDF_SIZE = 35; // Maximum PDF file size in MB
const MAX_FILE_SIZE = 50; // Maximum file size in MB for File Inputs API documents
const MAX_IMAGES = 5;    // Maximum number of images to keep in memory

// File extensions accepted by OpenAI File Inputs API
const FILE_INPUTS_ACCEPT = '.jpg,.jpeg,.png,.gif,.webp,.pdf,.xlsx,.docx,.pptx,.csv,.txt,.md,.json,.html,.xml';

// Helper: get Font Awesome icon class for a MIME type
function getDocumentIcon(mimeType) {
  const icons = {
    'application/pdf': 'fa-file-pdf',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'fa-file-excel',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'fa-file-word',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'fa-file-powerpoint',
    'text/csv': 'fa-file-csv',
    'text/plain': 'fa-file-lines',
    'text/markdown': 'fa-file-lines',
    'text/html': 'fa-file-code',
    'text/xml': 'fa-file-code',
    'application/json': 'fa-file-code'
  };
  return icons[mimeType] || 'fa-file';
}

// Helper: check if a MIME type is a document (non-image, non-PDF)
function isDocumentType(mimeType) {
  return mimeType && !mimeType.startsWith('image/') && mimeType !== 'application/pdf';
}

// MIME type mapping from file extensions
function getMimeTypeFromExtension(ext) {
  const map = {
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'csv': 'text/csv',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'json': 'application/json',
    'html': 'text/html',
    'xml': 'text/xml',
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp'
  };
  return map[(ext || '').toLowerCase()] || 'application/octet-stream';
}
const selectFileButton = $("#image-file");
let images = []; // Store multiple images/PDFs
let currentMaskData = null; // Store current mask data for image editing

// Function to limit the number of images in memory
function limitImageCount() {
  // Keep only the last MAX_IMAGES images
  if (images.length > MAX_IMAGES) {
    // Remove oldest non-document images first (keep PDFs/documents as they're often needed for context)
    const nonPdfImages = images.filter(img => img.type === undefined || img.type.startsWith('image/'));
    const pdfImages = images.filter(img => img.type && !img.type.startsWith('image/'));
    
    if (nonPdfImages.length > 0) {
      // Keep newest non-PDF images plus all PDFs
      const newestNonPdfImages = nonPdfImages.slice(-MAX_IMAGES);
      images = [...pdfImages, ...newestNonPdfImages].slice(-MAX_IMAGES);
    } else {
      // If only PDFs, just keep the newest MAX_IMAGES
      images = images.slice(-MAX_IMAGES);
    }
    
    // Update the display to reflect the limited images
    updateFileDisplay(images);
  }
}

// Modal event listener for cleanup when hidden
$("#imageModal").on("hidden.bs.modal", function () {
  $('#imageFile').val('');
  $('#imageUrlInput').val('');
  $('#uploadImage').prop('disabled', true);
  $(this).find(".size-error").html("");
});

// URL file add handler (Phase 3: URL reference for Responses API models)
$(document).on("click", "#addUrlFile", function () {
  const urlInput = $('#imageUrlInput').val().trim();
  if (!urlInput) return;

  try {
    const url = new URL(urlInput);
    // Only allow http(s) URLs to prevent javascript: or data: URI injection
    if (!url.protocol.startsWith('http')) {
      $("#select_image_error").html('<i class="fas fa-exclamation-circle"></i> Only HTTP/HTTPS URLs are supported');
      return;
    }
    const pathname = url.pathname;
    const ext = pathname.split('.').pop();
    const filename = decodeURIComponent(pathname.split('/').pop() || 'file').replace(/[<>"'&]/g, '_');
    const mimeType = getMimeTypeFromExtension(ext);

    const fileData = {
      title: filename,
      data: urlInput,
      type: mimeType,
      source: "url"
    };

    images.push(fileData);
    limitImageCount();
    updateFileDisplay(images);

    $('#imageUrlInput').val('');
    $("#select_image_error").html("");
  } catch (e) {
    $("#select_image_error").html(`
      <i class="fas fa-exclamation-circle"></i> Invalid URL
    `);
  }
});

// Clear images array when page is unloaded to free memory
$(window).on("beforeunload", function() {
  images = [];
  currentPdfData = null;
});

// File selection event listener
$("#imageFile").on("change", function() {
  // Clear any existing error message
  $("#select_image_error").html("");
  
  const file = this.files[0];
  $('#uploadImage').prop('disabled', !file);
});

// File selection button click handler
selectFileButton.on("click", function () {
  const selectedModel = $("#model").val();
  const isPdfEnabled = window.isPdfSupportedForModel ? window.isPdfSupportedForModel(selectedModel) : false;
  const isFileInputsEnabled = window.isFileInputsSupportedForModel ? window.isFileInputsSupportedForModel(selectedModel) : false;
  const currentApp = $("#apps").val();
  const isImageGenerationApp = window.isImageGenerationApp ? window.isImageGenerationApp(currentApp) : false;
  const allowPdfInImageApp = currentApp === "ImageGeneratorGemini3Preview";

  // Update modal UI based on model capabilities and app settings (3-tier)
  if (isFileInputsEnabled && !isImageGenerationApp) {
    // Tier 1: Full File Inputs API support (images + PDF + documents)
    $("#imageModalLabel").html('<i class="fas fa-file"></i> <span data-i18n="ui.modals.selectFile">Select File</span>');
    $("#imageFile").attr('accept', FILE_INPUTS_ACCEPT);
    const fileLabel = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.fileToImportAll') : 'File to import (images, PDF, XLSX, DOCX, CSV, etc.)';
    $("label[for='imageFile']").text(fileLabel);
  } else if (isPdfEnabled && (!isImageGenerationApp || allowPdfInImageApp)) {
    // Tier 2: PDF + images
    $("#imageModalLabel").html('<i class="fas fa-file"></i> Select Image or PDF File');
    $("#imageFile").attr('accept', '.jpg,.jpeg,.png,.gif,.webp,.pdf');
    const pdfLabel = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.fileToImportPdf') : 'File to import (.jpg, .jpeg, .png, .gif, .webp, .pdf)';
    $("label[for='imageFile']").text(pdfLabel);
  } else {
    // Tier 3: Images only
    $("#imageModalLabel").html('<i class="fas fa-image"></i> Select Image File');
    $("#imageFile").attr('accept', '.jpg,.jpeg,.png,.gif,.webp');
    const imageLabel = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.fileToImportImage') : 'File to import (.jpg, .jpeg, .png, .gif, .webp)';
    $("label[for='imageFile']").text(imageLabel);
  }

  // Show/hide URL input section for Responses API models
  const isResponsesApi = window.isResponsesApiModel ? window.isResponsesApiModel(selectedModel) : false;
  if (isResponsesApi && (isFileInputsEnabled || isPdfEnabled)) {
    $("#url-input-section").show();
  } else {
    $("#url-input-section").hide();
  }

  $("#imageModal").modal("show");
  setTimeout(() => {
    $("#imageFile").focus();
  }, 500);
});

// Upload button click handler
$("#uploadImage").on("click", function () {
  const fileInput = $('#imageFile')[0];
  const file = fileInput.files[0];
  const selectedModel = $("#model").val();
  const isPdfEnabled = window.isPdfSupportedForModel ? window.isPdfSupportedForModel(selectedModel) : false;
  const isFileInputsEnabled = window.isFileInputsSupportedForModel ? window.isFileInputsSupportedForModel(selectedModel) : false;
  const currentApp = $("#apps").val();
  const isImageGenerationApp = window.isImageGenerationApp ? window.isImageGenerationApp(currentApp) : false;
  const allowPdfInImageApp = currentApp === "ImageGeneratorGemini3Preview";

  if (file) {
    const fileSizeInMB = file.size / (1024 * 1024);
    const isDocument = isDocumentType(file.type);

    // Size checks
    if (file.type === 'application/pdf') {
      if (fileSizeInMB > MAX_PDF_SIZE) {
        $("#select_image_error").html(`
            <i class="fas fa-exclamation-circle"></i>
            PDF file size must be less than ${MAX_PDF_SIZE}MB.<br />
            Current size: ${fileSizeInMB.toFixed(1)}MB
        `);
        return;
      }
    } else if (isDocument) {
      if (fileSizeInMB > MAX_FILE_SIZE) {
        $("#select_image_error").html(`
            <i class="fas fa-exclamation-circle"></i>
            File size must be less than ${MAX_FILE_SIZE}MB.<br />
            Current size: ${fileSizeInMB.toFixed(1)}MB
        `);
        return;
      }
      // Document files require File Inputs API support
      if (!isFileInputsEnabled) {
        const docRestrictionMsg = getTranslation('ui.messages.docModelRestriction', 'This file type requires a model that supports File Inputs');
        setAlert(docRestrictionMsg, "error");
        $("#imageModal").modal("hide");
        return;
      }
    }

    // Validate PDF compatibility with selected model and app settings
    if (file.type === 'application/pdf') {
      if (isImageGenerationApp && !allowPdfInImageApp) {
        const pdfErrorMsg = typeof webUIi18n !== 'undefined' ? webUIi18n.t('ui.messages.pdfUploadError') : 'PDF files cannot be uploaded in image generation apps';
        setAlert(pdfErrorMsg, "error");
        $("#imageModal").modal("hide");
        return;
      }
      if (!isPdfEnabled && !allowPdfInImageApp) {
        const pdfRestrictionMsg = getTranslation('ui.messages.pdfModelRestriction', 'PDF files can only be uploaded when using a model that supports PDF input');
        setAlert(pdfRestrictionMsg, "error");
        $("#imageModal").modal("hide");
        return;
      }
    }

    $("#imageModal button").prop("disabled", true);

    try {
      if (file.type === 'application/pdf') {
        // Process PDF file
        fileToBase64(file, function(base64) {
          const fileData = {
            title: file.name,
            data: `data:${file.type};base64,${base64}`,
            type: file.type
          };
          currentPdfData = fileData; // Store the most recent PDF data globally
          images.push(fileData); // Add the PDF to existing images array
          limitImageCount();     // Limit the number of images in memory
          updateFileDisplay(images);
          $("#imageModal").modal("hide");
          $("#imageModal button").prop("disabled", false);
        });
      } else if (isDocument) {
        // Process document file (XLSX, DOCX, CSV, etc.) — no resize, raw base64
        fileToBase64(file, function(base64) {
          const fileData = {
            title: file.name,
            data: `data:${file.type};base64,${base64}`,
            type: file.type
          };
          images.push(fileData);
          limitImageCount();
          updateFileDisplay(images);
          $("#imageModal").modal("hide");
          $("#imageModal button").prop("disabled", false);
        });
      } else {
        // Process image file
        imageToBase64(file, function(base64) {
          const imageData = {
            title: file.name,
            data: `data:${file.type};base64,${base64}`,
            type: file.type
          };
          images.push(imageData);
          limitImageCount();     // Limit the number of images in memory
          updateFileDisplay(images);
          $("#imageModal").modal("hide");
          $("#imageModal button").prop("disabled", false);
        });
      }
    } catch (error) {
      $("#imageModal button").prop("disabled", false);
      $("#imageModal").modal("hide");
      const errorUploadingText = getTranslation('ui.messages.errorUploadingFile', 'Error uploading file');
      setAlert(`${errorUploadingText}: ${error}`, "error");
      return;
    }
  }
});

// Convert file to base64 - with Promise-based option
function fileToBase64(blob, callback) {
  // Legacy callback version for backward compatibility
  if (typeof callback === 'function') {
    const reader = new FileReader();
    reader.onload = function() {
      const base64 = reader.result.split(',')[1];
      callback(base64);
    };
    reader.onerror = function(error) {
      console.error('Error reading file:', error);
      callback(null);
    };
    reader.readAsDataURL(blob);
    return;
  }
  
  // Return a promise for modern usage
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = function() {
      const base64 = reader.result.split(',')[1];
      resolve(base64);
    };
    reader.onerror = function(error) {
      console.error('Error reading file:', error);
      reject(error);
    };
    reader.readAsDataURL(blob);
  });
}

// Update display for both images and PDFs
function updateFileDisplay(files) {
  $("#image-used").html(""); // Clear current display
  
  // Check if there's a mask image
  const hasMask = window.currentMaskData !== null;
  let maskData = null;
  let maskForImageIndex = -1;
  
  // If we have a mask, identify the associated base image
  if (hasMask && window.currentMaskData && window.currentMaskData.mask_for) {
    maskData = window.currentMaskData;
    // Find the index of the base image that this mask is for
    maskForImageIndex = files.findIndex(file => file.title === maskData.mask_for);
  }

  // Check if image generation is enabled in the current app
  const currentApp = $("#apps").val();
  const isImageGenerationEnabled = window.isImageGenerationApp ? 
    (window.isImageGenerationApp(currentApp) || 
     (apps[currentApp] && apps[currentApp].image_generation === "upload_only")) : false;
  
  // Check if mask editing is enabled - separate from basic image generation
  const isMaskEditingEnabled = window.isMaskEditingEnabled ? window.isMaskEditingEnabled(currentApp) : false;

  // Create display elements for each file
  files.forEach((file, index) => {
    if (file.source === 'url') {
      // Display URL-referenced file with link icon
      const icon = getDocumentIcon(file.type);
      $("#image-used").append(`
        <div class="file-container">
          <i class="fas fa-link"></i> <i class="fas ${icon}"></i> ${file.title}
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
    } else if (file.type === 'application/pdf') {
      // Display PDF file with icon and title
      $("#image-used").append(`
        <div class="file-container">
          <i class="fas fa-file-pdf"></i> ${file.title}
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
    } else if (isDocumentType(file.type)) {
      // Display document file (XLSX, DOCX, CSV, etc.) with appropriate icon
      const icon = getDocumentIcon(file.type);
      $("#image-used").append(`
        <div class="file-container">
          <i class="fas ${icon}"></i> ${file.title}
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
    } else if (hasMask && maskData && index === maskForImageIndex && maskForImageIndex !== -1) {
      // This is the base image for which we have a mask - display as overlay
      
      const overlayDisplay = `
        <div class="mask-overlay-container">
          <img class='base-image' alt='${file.title}' src='${file.data}' />
          <img class='mask-overlay opacity-60' alt='${maskData.title}' src='${maskData.display_data || maskData.data}' />
          <div class="mask-overlay-label">MASK</div>
          <div class="mask-controls">
            <button class='btn btn-sm btn-danger remove-mask' data-index='${index}' tabindex="99">
              <i class="fas fa-times"></i> Remove Mask
            </button>
            <button class='btn btn-sm btn-secondary toggle-mask' tabindex="100">
              <i class="fas fa-eye-slash"></i> Toggle Mask
            </button>
          </div>
        </div>
      `;
      $("#image-used").append(overlayDisplay);
    } else if (!hasMask || !maskData || file.title !== maskData.title) { // Skip displaying the mask image separately
      // Display image with thumbnail
      const imageActions = `
        <div class="image-actions">
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
          ${isMaskEditingEnabled ? 
            `<button class='btn btn-primary btn-sm create-mask ml-2' data-index='${index}' tabindex="100">
              <i class="fas fa-brush"></i> Create Mask
            </button>` : ''
          }
        </div>
      `;
      
      const imageDisplay = `
        <div class="image-container">
          <img class='base64-image' alt='${file.title}' src='${file.data}' data-type='${file.type}' />
          ${imageActions}
        </div>
      `;
      $("#image-used").append(imageDisplay);
    }
  });

  // Add event listeners for file removal
  $(".remove-file").on("click", function () {
    const index = $(this).data("index");
    const removedFile = images[index];

    // Remove only the selected file (image or PDF)
    if (removedFile.type === 'application/pdf' && removedFile === currentPdfData) {
      // If removing the current PDF reference, set it to null
      currentPdfData = null;
    }
    
    // If this is the base image for a mask, also remove the mask
    if (window.currentMaskData && window.currentMaskData.mask_for && window.currentMaskData.mask_for === removedFile.title) {
      // Find and remove the mask from images array
      const maskIndex = images.findIndex(img => img.title === window.currentMaskData.title);
      if (maskIndex !== -1) {
        images.splice(maskIndex, 1);
      }
      window.currentMaskData = null;
    }
    
    // Remove the file from the images array
    images.splice(index, 1);
    updateFileDisplay(images);
  });
  
  // Add event listeners for mask toggle
  $(".toggle-mask").on("click", function() {
    const $maskOverlay = $(this).closest(".mask-overlay-container").find(".mask-overlay");
    const $icon = $(this).find("i");

    if ($maskOverlay.hasClass("opacity-0")) {
      // Show mask
      $maskOverlay.removeClass("opacity-0").addClass("opacity-60");
      $icon.removeClass("fa-eye").addClass("fa-eye-slash");
    } else {
      // Hide mask
      $maskOverlay.removeClass("opacity-60").addClass("opacity-0");
      $icon.removeClass("fa-eye-slash").addClass("fa-eye");
    }
  });
  
  // Add event listeners for mask removal
  $(".remove-mask").on("click", function() {
    const index = $(this).data("index");
    const maskFilename = $(this).data("mask-filename");
    const originalImageTitle = $(this).closest(".mask-overlay-container").data("original-image");
    
    // Only remove the mask, not the base image
    if (window.currentMaskData) {
      // Find and remove the mask from images array
      const maskToRemove = maskFilename || (window.currentMaskData ? window.currentMaskData.title : null);
      if (maskToRemove) {
        const maskIndex = images.findIndex(img => img.title === maskToRemove);
        if (maskIndex !== -1) {
          images.splice(maskIndex, 1);
        }
      }
      window.currentMaskData = null;
    }
    
    // Remove the mask overlay container
    $(this).closest(".mask-overlay-container").remove();
    
    // Show the original image if it exists and is hidden
    if (originalImageTitle) {
      $(`.image-container:has(img[alt="${originalImageTitle}"]):hidden`).fadeIn();
    }
    
    // Update display to show changes
    updateFileDisplay(images);
    
    // Show success alert
    const maskRemovedText = getTranslation('ui.messages.maskRemoved', 'Mask removed');
    setAlert(`<i class='fa-solid fa-circle-check'></i> ${maskRemovedText}`, "success");
  });
  
  // Add event listeners for mask creation
  $(".create-mask").on("click", function() {
    const index = $(this).data("index");
    
    // Check if mask editing is enabled in the current app
    const currentApp = $("#apps").val();
    const isMaskEditingEnabled = window.isMaskEditingEnabled ? window.isMaskEditingEnabled(currentApp) : false;
    
    if (!isMaskEditingEnabled) {
      const maskNotAvailableText = getTranslation('ui.messages.maskEditingNotAvailable', 'Mask editing is not available in this app');
      setAlert(maskNotAvailableText, "error");
      return;
    }
    
    if (typeof window.openMaskEditor === 'function') {
      window.openMaskEditor(images[index]);
    } else {
      console.error("Mask editor not loaded");
      const maskEditorNotAvailableText = getTranslation('ui.messages.maskEditorNotAvailable', 'Mask editor not available');
      setAlert(maskEditorNotAvailableText, "error");
    }
  });
}

// Clear all images and mask data - call when switching apps
function clearAllImages() {
  images = [];
  currentMaskData = null;
  updateFileDisplay(images);
}

// Export functions to window for browser environment
window.fileToBase64 = fileToBase64;
window.imageToBase64 = imageToBase64;
window.updateFileDisplay = updateFileDisplay;
window.limitImageCount = limitImageCount;
window.clearAllImages = clearAllImages;
window.getDocumentIcon = getDocumentIcon;
window.isDocumentType = isDocumentType;
window.getMimeTypeFromExtension = getMimeTypeFromExtension;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    fileToBase64,
    imageToBase64,
    updateFileDisplay,
    limitImageCount,
    getDocumentIcon,
    isDocumentType,
    getMimeTypeFromExtension,
    MAX_FILE_SIZE,
    MAX_PDF_SIZE
  };
}

// Convert and resize image to base64 - with Promise-based option
function imageToBase64(blob, callback) {
  // Legacy callback version for backward compatibility
  if (typeof callback === 'function') {
    const reader = new FileReader();
    reader.onload = function (e) {
      const dataUrl = reader.result;
      const image = new Image();
      
      image.onload = function () {
        try {
          let width = image.width;
          let height = image.height;
          const MAX_LONG_SIDE = 2000;
          const MAX_SHORT_SIDE = 768;

          // Determine the long and short sides
          const longSide = Math.max(width, height);
          const shortSide = Math.min(width, height);

          // Check if the image needs resizing
          if (longSide > MAX_LONG_SIDE || shortSide > MAX_SHORT_SIDE) {
            const longSideScale = MAX_LONG_SIDE / longSide;
            const shortSideScale = MAX_SHORT_SIDE / shortSide;
            const scale = Math.min(longSideScale, shortSideScale);
            width = width * scale;
            height = height * scale;

            // Resize the image using canvas
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(image, 0, 0, width, height);
            const resizedDataUrl = canvas.toDataURL(blob.type);
            const base64 = resizedDataUrl.split(',')[1];
            callback(base64);
          } else {
            // Use original base64 if no resizing needed
            const base64 = dataUrl.split(',')[1];
            callback(base64);
          }
        } catch (error) {
          console.error('Error processing image:', error);
          // In case of error, update display with current images to prevent UI lockup
          updateFileDisplay(images);
          // Show an error message to the user
          const errorProcessingText = getTranslation('ui.messages.errorProcessingImage', 'Error processing image');
          setAlert(`<i class="fas fa-exclamation-circle"></i> ${errorProcessingText}: ${error.message}`, "error");
          // Close modal if it's open
          $("#imageModal").modal("hide");
          callback(null);
        }
      };
      
      image.onerror = function(error) {
        console.error('Error loading image:', error);
        // In case of error, update display with current images to prevent UI lockup
        updateFileDisplay(images);
        // Show an error message to the user
        const errorLoadingText = getTranslation('ui.messages.errorLoadingImage', 'Error loading image');
        setAlert(`<i class="fas fa-exclamation-circle"></i> ${errorLoadingText}`, "error");
        // Close modal if it's open
        $("#imageModal").modal("hide");
        callback(null);
      };
      
      image.src = dataUrl;
    };
    
    reader.onerror = function(error) {
      console.error('Error reading file:', error);
      // Show an error message to the user
      const errorReadingText = getTranslation('ui.messages.errorReadingFile', 'Error reading file');
      setAlert(`<i class="fas fa-exclamation-circle"></i> ${errorReadingText}`, "error");
      // Close modal if it's open
      $("#imageModal").modal("hide");
      callback(null);
    };
    
    reader.readAsDataURL(blob);
    return;
  }
  
  // Return a promise for modern usage
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    
    reader.onload = function (e) {
      const dataUrl = reader.result;
      const image = new Image();
      
      image.onload = function () {
        try {
          let width = image.width;
          let height = image.height;
          const MAX_LONG_SIDE = 2000;
          const MAX_SHORT_SIDE = 768;

          // Determine the long and short sides
          const longSide = Math.max(width, height);
          const shortSide = Math.min(width, height);

          // Check if the image needs resizing
          if (longSide > MAX_LONG_SIDE || shortSide > MAX_SHORT_SIDE) {
            const longSideScale = MAX_LONG_SIDE / longSide;
            const shortSideScale = MAX_SHORT_SIDE / shortSide;
            const scale = Math.min(longSideScale, shortSideScale);
            width = width * scale;
            height = height * scale;

            // Resize the image using canvas
            const canvas = document.createElement('canvas');
            canvas.width = width;
            canvas.height = height;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(image, 0, 0, width, height);
            const resizedDataUrl = canvas.toDataURL(blob.type);
            const base64 = resizedDataUrl.split(',')[1];
            resolve(base64);
          } else {
            // Use original base64 if no resizing needed
            const base64 = dataUrl.split(',')[1];
            resolve(base64);
          }
        } catch (error) {
          console.error('Error processing image:', error);
          // In case of error, update display with current images to prevent UI lockup
          updateFileDisplay(images);
          // Show an error message to the user
          const errorProcessingText = getTranslation('ui.messages.errorProcessingImage', 'Error processing image');
          setAlert(`<i class="fas fa-exclamation-circle"></i> ${errorProcessingText}: ${error.message}`, "error");
          // Close modal if it's open
          $("#imageModal").modal("hide");
          reject(error);
        }
      };
      
      image.onerror = function(error) {
        console.error('Error loading image:', error);
        // In case of error, update display with current images to prevent UI lockup
        updateFileDisplay(images);
        // Show an error message to the user
        const errorLoadingText = getTranslation('ui.messages.errorLoadingImage', 'Error loading image');
        setAlert(`<i class="fas fa-exclamation-circle"></i> ${errorLoadingText}`, "error");
        // Close modal if it's open
        $("#imageModal").modal("hide");
        reject(error);
      };
      
      image.src = dataUrl;
    };
    
    reader.onerror = function(error) {
      console.error('Error reading file:', error);
      // Show an error message to the user
      const errorReadingText = getTranslation('ui.messages.errorReadingFile', 'Error reading file');
      setAlert(`<i class="fas fa-exclamation-circle"></i> ${errorReadingText}`, "error");
      // Close modal if it's open
      $("#imageModal").modal("hide");
      reject(error);
    };
    
    reader.readAsDataURL(blob);
  });
}
