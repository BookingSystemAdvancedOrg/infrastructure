// Viewer request, admin app /api/*: strip the /api prefix (API Gateway's
// routes start at /), and pass the viewer's IP and the host the browser
// used. These overwrite anything the browser sent under the same names.
// The API only trusts them together with the x-booqy-edge secret, which
// CloudFront adds as an origin custom header (never visible to browsers).
function handler(event) {
  var request = event.request;
  request.uri = request.uri.replace(/^\/api(?=\/)/, '');
  request.headers['x-booqy-viewer-ip'] = { value: event.viewer.ip };
  request.headers['x-booqy-viewer-host'] = { value: request.headers.host ? request.headers.host.value : '' };
  return request;
}
