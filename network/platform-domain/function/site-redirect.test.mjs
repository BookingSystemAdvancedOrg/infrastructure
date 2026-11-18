// node --test network/platform-domain/function/
// The restaurant sites' redirect function, with its Terraform template filled
// in as redirects.tf does and the key value store faked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const template = readFileSync(new URL('./site-redirect.js', import.meta.url), 'utf8');

function load(keys, fail = false) {
  const source = template.replaceAll('${kvs_id}', 'kvs-test').replace("import cf from 'cloudfront';", '');
  assert.ok(!source.includes('${'), 'every template value is filled in');
  const cf = {
    kvs(id) {
      assert.equal(id, 'kvs-test');
      return {
        async get(key) {
          if (fail) throw new Error('KVS unavailable');
          if (!(key in keys)) throw new Error('KeyNotFound');
          return keys[key];
        }
      };
    }
  };
  return new Function('cf', source + '\nreturn handler;')(cf);
}

const KEYS = {
  'pizzeria-roma.booqy.se': 'roma.se',
  'www.roma.se': 'roma.se',
  'pizzeria-roma.dev.booqy.se': 'dev.roma.se',
  'loop.booqy.se': 'loop.booqy.se',
  'bad.booqy.se': 'https://evil.example/x',
  'upper.booqy.se': 'Roma.SE'
};
const handler = load(KEYS);

function event(host, uri, querystring = {}) {
  return { request: { method: 'GET', uri, querystring, headers: host === null ? {} : { host: { value: host } } } };
}

test('the slug address answers 301 to the live own domain, path kept', async () => {
  const out = await handler(event('pizzeria-roma.booqy.se', '/meny'));
  assert.equal(out.statusCode, 301);
  assert.equal(out.headers.location.value, 'https://roma.se/meny');
  assert.equal(out.headers['cache-control'].value, 'max-age=3600');
});

test('www goes to the apex, dev slug to dev.<domain>', async () => {
  assert.equal((await handler(event('www.roma.se', '/'))).headers.location.value, 'https://roma.se/');
  assert.equal((await handler(event('pizzeria-roma.dev.booqy.se', '/boka'))).headers.location.value,
    'https://dev.roma.se/boka');
});

test('the query string is kept, repeated keys and flags too', async () => {
  const qs = {
    utm_source: { value: 'qr' },
    t: { value: '4', multiValue: [{ value: '4' }, { value: '5' }] },
    preview: { value: '' },
    q: { value: 'a%20b' }
  };
  const out = await handler(event('pizzeria-roma.booqy.se', '/bord', qs));
  assert.equal(out.headers.location.value, 'https://roma.se/bord?utm_source=qr&t=4&t=5&preview&q=a%20b');
});

test('host casing and a port do not matter', async () => {
  assert.equal((await handler(event('Pizzeria-Roma.BOOQY.se:443', '/'))).headers.location.value, 'https://roma.se/');
  assert.equal((await handler(event('upper.booqy.se', '/'))).headers.location.value, 'https://roma.se/');
});

test('unknown hosts, the own domain itself and loops pass through', async () => {
  for (const host of ['roma.se', 'other.booqy.se', 'loop.booqy.se', '', null]) {
    const req = event(host, '/x').request;
    assert.equal(await handler({ request: req }), req, String(host));
  }
});

test('a value that is not a host name is ignored', async () => {
  const req = event('bad.booqy.se', '/').request;
  assert.equal(await handler({ request: req }), req);
});

test('certificate validation paths are never redirected', async () => {
  const req = event('pizzeria-roma.booqy.se', '/.well-known/acme-challenge/abc').request;
  assert.equal(await handler({ request: req }), req);
});

test('a key value store error fails open', async () => {
  const broken = load(KEYS, true);
  const req = event('pizzeria-roma.booqy.se', '/').request;
  assert.equal(await broken({ request: req }), req);
});

test('a client-side route loads index.html, files and certificate paths keep their path', async () => {
  for (const [uri, want] of [
    ['/', '/index.html'],
    ['/boka-bord', '/index.html'],
    ['/evenemang/01JEVENT', '/index.html'],
    ['/assets/index-abc123.js', '/assets/index-abc123.js'],
    ['/favicon.ico', '/favicon.ico'],
    ['/.well-known/acme-challenge/token', '/.well-known/acme-challenge/token'],
  ]) {
    const out = await handler(event('unknown.booqy.se', uri));
    assert.equal(out.uri, want, uri);
  }
});

test('a redirect keeps the original path, not index.html', async () => {
  const out = await handler(event('pizzeria-roma.booqy.se', '/meny'));
  assert.equal(out.statusCode, 301);
  assert.equal(out.headers.location.value, 'https://roma.se/meny');
});
