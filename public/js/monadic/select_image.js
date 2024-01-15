//////////////////////////////
// Read file contents 
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
        blobToBase64(file, function (base64) {
          imageTitle = file.name;
          imageType = file.type;
          imageData = "data:" + imageType + ";base64," + base64;
          $("#imageModal button").prop("disabled", false);
          $("#imageModal").modal("hide");
          $("#image-used").html("Image: " + imageTitle);
          $("#image-base64").html("<img style='max-width: 400px; max-height: 200px;' src='data:" + imageType + ";base64," + base64 + "' />");
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

function blobToBase64(blob, callback) {
  const reader = new FileReader();
  reader.onload = function () {
    const dataUrl = reader.result;
    const base64 = dataUrl.split(',')[1];
    callback(base64);
  };
  reader.readAsDataURL(blob);
}
