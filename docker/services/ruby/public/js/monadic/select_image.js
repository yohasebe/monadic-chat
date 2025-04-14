//////////////////////////////
// Read image/PDF file contents 
//////////////////////////////

// Notice that PDF is only for Anthropic Claude models (Nov 2024)

const MAX_PDF_SIZE = 35; // Maximum PDF file size in MB
const MAX_IMAGES = 5;    // Maximum number of images to keep in memory
const selectFileButton = $("#image-file");
let images = []; // Store multiple images/PDFs

// Function to limit the number of images in memory
function limitImageCount() {
  // Keep only the last MAX_IMAGES images
  if (images.length > MAX_IMAGES) {
    // Remove oldest non-PDF images first (keep PDFs as they're often needed for context)
    const nonPdfImages = images.filter(img => img.type !== 'application/pdf');
    const pdfImages = images.filter(img => img.type === 'application/pdf');
    
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
  $('#uploadImage').prop('disabled', true);
  $(this).find(".size-error").html("");
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
  const isPdfEnabled = /sonnet|gemini|4o|4o-mini|o1|gpt-4\.\d/.test(selectedModel);

  // Update modal UI based on model capabilities
  if (isPdfEnabled) {
    $("#imageModalLabel").html('<i class="fas fa-file"></i> Select Image or PDF File');
    $("#imageFile").attr('accept', '.jpg,.jpeg,.png,.gif,.pdf');
    $("label[for='imageFile']").text('File to import (.jpg, .jpeg, .png, .gif, .pdf)');
  } else {
    $("#imageModalLabel").html('<i class="fas fa-image"></i> Select Image File');
    $("#imageFile").attr('accept', '.jpg,.jpeg,.png,.gif');
    $("label[for='imageFile']").text('File to import (.jpg, .jpeg, .png, .gif)');
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
  const isPdfEnabled = /sonnet|gemini|4o|4o-mini|o1|gpt-4\.\d/.test(selectedModel);

  if (file) {
    // Check file size for PDF files (35MB limit)
    if (file.type === 'application/pdf') {
      const fileSizeInMB = file.size / (1024 * 1024);
      if (fileSizeInMB > MAX_PDF_SIZE) {
        $("#select_image_error").html(`
            <i class="fas fa-exclamation-circle"></i> 
            PDF file size must be less than ${MAX_PDF_SIZE}MB.<br />
            Current size: ${fileSizeInMB.toFixed(1)}MB
        `);
        return;
      }
    }

    // Validate PDF compatibility with selected model
    if (file.type === 'application/pdf' && !isPdfEnabled) {
      setAlert("PDF files can only be uploaded when using a model that supports PDF input", "error");
      $("#imageModal").modal("hide");
      return;
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
      setAlert(`Error uploading file: ${error}`, "error");
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

  // Create display elements for each file
  files.forEach((file, index) => {
    if (file.type === 'application/pdf') {
      // Display PDF file with icon and title
      $("#image-used").append(`
        <div class="file-container">
          <i class="fas fa-file-pdf"></i> ${file.title}
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
    } else {
      // Display image with thumbnail
      $("#image-used").append(`
        <div class="image-container">
          <img class='base64-image' alt='${file.title}' src='${file.data}' data-type='${file.type}' />
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
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
    // Remove the file from the images array
    images.splice(index, 1);
    updateFileDisplay(images);
  });
}

// Export functions to window for browser environment
window.fileToBase64 = fileToBase64;
window.imageToBase64 = imageToBase64;
window.updateFileDisplay = updateFileDisplay;
window.limitImageCount = limitImageCount;

// Support for Jest testing environment (CommonJS)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    fileToBase64,
    imageToBase64,
    updateFileDisplay,
    limitImageCount
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
          callback(null);
        }
      };
      
      image.onerror = function(error) {
        console.error('Error loading image:', error);
        callback(null);
      };
      
      image.src = dataUrl;
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
          reject(error);
        }
      };
      
      image.onerror = function(error) {
        console.error('Error loading image:', error);
        reject(error);
      };
      
      image.src = dataUrl;
    };
    
    reader.onerror = function(error) {
      console.error('Error reading file:', error);
      reject(error);
    };
    
    reader.readAsDataURL(blob);
  });
}
