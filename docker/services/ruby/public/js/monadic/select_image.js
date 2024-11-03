//////////////////////////////
// Read image/PDF file contents 
//////////////////////////////

// Notice that PDF is only for Anthropic Claude models (Nov 2024)

const MAX_PDF_SIZE = 35; // Maximum PDF file size in MB
const selectFileButton = $("#image-file");
let images = []; // Store multiple images/PDFs

// Modal event listener for cleanup when hidden
$("#imageModal").on("hidden.bs.modal", function () {
  $('#imageFile').val('');
  $('#uploadImage').prop('disabled', true);
  $(this).find(".size-error").html("");
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
  const isPdfEnabled = selectedModel.includes("sonnet");

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
});

// Upload button click handler
$("#uploadImage").on("click", function () {
  const fileInput = $('#imageFile')[0];
  const file = fileInput.files[0];
  const selectedModel = $("#model").val();
  const isPdfEnabled = selectedModel.includes("sonnet");

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
      setAlert("PDF files can only be uploaded when using a Sonnet model.", "error");
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
          currentPdfData = fileData; // Store PDF data globally
          images = [fileData]; // Replace existing images with PDF
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

// Convert file to base64
function fileToBase64(blob, callback) {
  const reader = new FileReader();
  reader.onload = function() {
    const base64 = reader.result.split(',')[1];
    callback(base64);
  };
  reader.readAsDataURL(blob);
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

    if (removedFile.type === 'application/pdf') {
      // Clear all PDF-related data
      currentPdfData = null;
      images = [];
    } else {
      // Remove only the selected image
      images.splice(index, 1);
    }
    updateFileDisplay(images);
  });
}

// Convert and resize image to base64
function imageToBase64(blob, callback) {
  const reader = new FileReader();
  reader.onload = function (e) {
    const dataUrl = reader.result;
    const image = new Image();
    image.onload = function () {
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
    };
    image.src = dataUrl;
  };
  reader.readAsDataURL(blob);
}
