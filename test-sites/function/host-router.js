// Test sites sandbox, viewer request (cloudfront-js-2.0). Terraform template:
// main_domain, dev_domain and kvs_id are filled in by test-sites/main.tf.
//
// <label>.<main_domain> -> /main/sites/<tenantId>/<path>
// <label>.<dev_domain>  -> /dev/sites/<tenantId>/<path>
//
// The label (a test customer's slug, or a mapped own domain: example-se for
// example.se) is looked up in the key value store (label -> tenantId),
// written by the site-repo function. A path without a file extension is a
// client-side route of the site: index.html. /robots.txt is the sandbox's
// own (Disallow: /). An unknown host gets a 404 page, never another site.
import cf from 'cloudfront';

const kvs = cf.kvs('${kvs_id}');
const ZONES = [['.${dev_domain}', 'dev'], ['.${main_domain}', 'main']];
const LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
const FOLDER = /^[A-Za-z0-9_-]{1,64}$/;

function notFound() {
  return {
    statusCode: 404,
    statusDescription: 'Not Found',
    headers: {
      'content-type': { value: 'text/html; charset=utf-8' },
      'cache-control': { value: 'no-store' },
      'x-robots-tag': { value: 'noindex, nofollow' }
    },
    body: {
      encoding: 'text',
      data: '<!doctype html><html lang="sv"><meta charset="utf-8"><meta name="robots" content="noindex">' +
        '<title>Sidan finns inte</title><body style="font-family:system-ui;padding:2rem">' +
        '<h1>Sidan finns inte</h1><p>Den här testsajten finns inte (längre).</p></body></html>'
    }
  };
}

function site(host) {
  for (let i = 0; i < ZONES.length; i++) {
    const suffix = ZONES[i][0];
    if (host.length > suffix.length && host.endsWith(suffix)) {
      return { label: host.slice(0, host.length - suffix.length), stage: ZONES[i][1] };
    }
  }
  return null;
}

function sitePath(uri) {
  const last = uri.slice(uri.lastIndexOf('/') + 1);
  if (uri.indexOf('..') !== -1 || last === '' || last.indexOf('.') === -1) {
    return '/index.html';
  }
  return uri;
}

async function handler(event) {
  const request = event.request;
  const header = request.headers.host;
  const host = (header && header.value ? header.value : '').toLowerCase().split(':')[0];
  const found = site(host);
  if (!found || !LABEL.test(found.label)) {
    return notFound();
  }
  let folder;
  try {
    folder = await kvs.get(found.label);
  } catch (e) {
    return notFound();
  }
  if (typeof folder !== 'string' || !FOLDER.test(folder)) {
    return notFound();
  }
  if (request.uri === '/robots.txt') {
    request.uri = '/_platform/robots.txt';
    return request;
  }
  // The sandbox's own 404 page (the distribution's error responses) stays
  // where it is, should the router see that fetch.
  if (request.uri === '/_platform/404.html') {
    return request;
  }
  request.uri = '/' + found.stage + '/sites/' + folder + sitePath(request.uri);
  return request;
}
