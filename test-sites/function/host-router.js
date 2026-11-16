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
//
// Once a mapped own domain is live, guests only ever see it (as in prod):
// the slug's label holds ">example-se" instead of the tenantId, and
// <slug>.<zone> answers with a 301 to example-se.<same zone>, path and
// query kept (written and cleared by the site-repo function, testHost
// redirect). A value that is not ">" + a label is treated as a folder.
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
      return { label: host.slice(0, host.length - suffix.length), stage: ZONES[i][1], suffix: suffix };
    }
  }
  return null;
}

function query(qs) {
  const parts = [];
  const keys = Object.keys(qs || {});
  for (let i = 0; i < keys.length; i++) {
    const entry = qs[keys[i]];
    const values = entry.multiValue ? entry.multiValue : [entry];
    for (let j = 0; j < values.length; j++) {
      const value = values[j].value;
      parts.push(value === '' || value === undefined ? keys[i] : keys[i] + '=' + value);
    }
  }
  return parts.join('&');
}

function moved(target, suffix, request) {
  const qs = query(request.querystring);
  return {
    statusCode: 301,
    statusDescription: 'Moved Permanently',
    headers: {
      location: { value: 'https://' + target + suffix + request.uri + (qs ? '?' + qs : '') },
      'cache-control': { value: 'max-age=300' },
      'x-robots-tag': { value: 'noindex, nofollow' }
    }
  };
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
  if (typeof folder === 'string' && folder.charAt(0) === '>') {
    const target = folder.slice(1);
    if (!LABEL.test(target) || target === found.label) {
      return notFound();
    }
    return moved(target, found.suffix, request);
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
