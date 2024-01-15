//////////////////////////////
// Read image file contents 
//////////////////////////////

const selectFileButton = $("#image-file");

let imageTitle;
let imageData;
let imageType;
let imageSize;

selectFileButton.on("click", function () {
  $("#imageModal").modal("show");

  const fileImage = $('#imageFile');
  const imageButton = $('#uploadImage');

  let fileInput;
  let file;

  $("#imageModal").on("hidden.bs.modal", function () {
    fileImage.val('');
    imageButton.prop('disabled', true);
  });

  fileImage.on('change', function() {
    if (fileImage[0].files.length > 0) {
      imageButton.prop('disabled', false);
    }
  });

  $("#uploadImage").on("click", function () {
    fileInput = fileImage[0];
    file = fileInput.files[0];

    if (file) {
      $("#imageModal button").prop("disabled", true);

      try {
        imageToBase64(file, function (base64) {
          imageTitle = file.name;
          imageType = file.type;
          imageData = "data:" + imageType + ";base64," + base64;
          $("#imageModal button").prop("disabled", false);
          $("#imageModal").modal("hide");
          $("#image-used").html("Image: " + imageTitle);
          $("#image-base64").html("<img class='base64-image' src='data:" + imageType + ";base64," + base64 + "' />");
        });
      } catch (error) {
        $("#imageModal button").prop("disabled", false);
        $("#imageModal").modal("hide");
        setAlert(`Error uploading file: ${error}`, "danger");
        return;
      }
    }
  });
});

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
