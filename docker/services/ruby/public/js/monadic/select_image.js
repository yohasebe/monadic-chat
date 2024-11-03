//////////////////////////////
// Read image/PDF file contents 
//////////////////////////////

// Notice that PDF is only for Anthropic Claude models (Nov 2024)

const selectFileButton = $("#image-file");

let images = []; // Store multiple images/PDFs

selectFileButton.on("click", function () {
  const selectedModel = $("#model").val();
  const isPdfEnabled = selectedModel.includes("sonnet");
  
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

  const fileImage = $('#imageFile');
  const imageButton = $('#uploadImage');

  $("#imageModal").on("hidden.bs.modal", function () {
    fileImage.val('');
    imageButton.prop('disabled', true);
  });

  // Update accept attribute to include PDFs
  fileImage.attr('accept', '.jpg,.jpeg,.png,.gif,.pdf');

  fileImage.on('change', function () {
    if (fileImage[0].files.length > 0) {
      imageButton.prop('disabled', false);
    }
  });

  $("#uploadImage").off("click").on("click", function () {
    const fileInput = fileImage[0];
    const file = fileInput.files[0];
    const selectedModel = $("#model").val();
    const isPdfEnabled = selectedModel.includes("sonnet");

    if (file) {
      if (file.type === 'application/pdf' && !isPdfEnabled) {
        setAlert("PDF files can only be uploaded when using a Sonnet model.", "error");
        $("#imageModal").modal("hide");
        return;
      }

      $("#imageModal button").prop("disabled", true);

      try {
        if (file.type === 'application/pdf') {
          // Handle PDF files
          fileToBase64(file, function(base64) {
            const fileData = {
              title: file.name,
              data: `data:${file.type};base64,${base64}`,
              type: file.type
            };
            images.push(fileData);
            updateFileDisplay(images);
            $("#imageModal").modal("hide");
            $("#imageModal button").prop("disabled", false);
          });
        } else {
          // Handle image files
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
});

// New function to handle PDF files
function fileToBase64(blob, callback) {
  const reader = new FileReader();
  reader.onload = function() {
    const base64 = reader.result.split(',')[1];
    callback(base64);
  };
  reader.readAsDataURL(blob);
}

// Update display function to handle both images and PDFs
function updateFileDisplay(files) {
  $("#image-used").html(""); 
  files.forEach((file, index) => {
    if (file.type === 'application/pdf') {
      $("#image-used").append(`
        <div class="file-container">
          <i class="fas fa-file-pdf"></i> ${file.title}
          <button class='btn btn-secondary btn-sm remove-file' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
    } else {
      $("#image-used").append(`
        <div class="image-container">
          <img class='base64-image' alt='${file.title}' src='${file.data}' data-type='${file.type}' />
          <button class='btn btn-secondary btn-sm remove-image' data-index='${index}' tabindex="99">
            <i class="fas fa-times"></i>
          </button>
        </div>
      `);
    }
  });

  // Add event listener for removing files
  $(".remove-image, .remove-file").on("click", function () {
    const index = $(this).data("index");
    images.splice(index, 1);
    updateFileDisplay(images);
  });
}

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

        // Resize the image with a canvas
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(image, 0, 0, width, height);
        const resizedDataUrl = canvas.toDataURL(blob.type);
        const base64 = resizedDataUrl.split(',')[1];
        callback(base64);
      } else {
        // No resizing necessary, use original base64
        const base64 = dataUrl.split(',')[1];
        callback(base64);
      }
    };
    image.src = dataUrl;
  };
  reader.readAsDataURL(blob);
}

// Function to update the image display
function updateImageDisplay(images) {
  $("#image-used").html(""); // Clear previous images
  images.forEach((image, index) => {
    $("#image-used").append(`
      <div class="image-container">
        <img class='base64-image' alt='${image.title}' src='${image.data}' data-type='${image.type}' />
        <button class='btn btn-secondary btn-sm remove-image' data-index='${index}' tabindex="99"><i class="fas fa-times"></i></button>
      </div>
    `);
  });

  // Add event listener for removing images
  $(".remove-image").on("click", function () {
    const index = $(this).data("index");
    images.splice(index, 1); // Remove the image from the array
    updateImageDisplay(images); // Update the display
  });
}
