// Viewer request, admin app (default behavior):
//
// 1. A request for a legacy hostname (restaurant.<domain>, the admin app's
//    first name) is redirected (301) to the same path on canonical_host
//    (restaurang.<domain>). Only page loads go through this behavior - the
//    /api/* behavior has no function, so /api links in emails already sent
//    keep working on the old name.
// 2. Paths without a file extension are client-side routes of the SPA, so
//    they load /index.html. Done here instead of with custom_error_response
//    because those apply to the whole distribution and would turn the API's
//    own 403/404 answers under /api/* into the app's HTML.
//
// Rendered by Terraform (templatefile): the values below come from
// network/cloudfront/private (canonical_host, legacy_hosts).
var CANONICAL_HOST = '${canonical_host}';
var LEGACY_HOSTS = ${legacy_hosts};

function handler(event) {
  var request = event.request;
  var host = request.headers.host ? request.headers.host.value.toLowerCase() : '';
  if (CANONICAL_HOST && LEGACY_HOSTS.indexOf(host) !== -1) {
    var query = [];
    for (var key in request.querystring) {
      var param = request.querystring[key];
      if (param.multiValue) {
        for (var i = 0; i < param.multiValue.length; i++) {
          query.push(key + '=' + param.multiValue[i].value);
        }
      } else {
        query.push(param.value === '' ? key : key + '=' + param.value);
      }
    }
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: {
        location: { value: 'https://' + CANONICAL_HOST + request.uri + (query.length ? '?' + query.join('&') : '') },
        'cache-control': { value: 'max-age=86400' },
      },
    };
  }
  var uri = request.uri;
  var last = uri.substring(uri.lastIndexOf('/') + 1);
  if (last.indexOf('.') === -1) {
    request.uri = '/index.html';
  }
  return request;
}
