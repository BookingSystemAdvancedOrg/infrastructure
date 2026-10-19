// Viewer request, admin app (default behavior): paths without a file
// extension are client-side routes of the SPA, so they load /index.html.
// Done here instead of with custom_error_response because those apply to
// the whole distribution and would turn the API's own 403/404 answers under
// /api/* into the app's HTML.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var last = uri.substring(uri.lastIndexOf('/') + 1);
  if (last.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
