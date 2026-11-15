// node --test test-sites/function/
// The sandbox's CloudFront Function, with its Terraform template filled in
// as test-sites/main.tf does and the key value store faked.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const template = readFileSync(new URL('./host-router.js', import.meta.url), 'utf8');

function load(keys) {
  const source = template
    .replaceAll('${kvs_id}', 'kvs-test')
    .replaceAll('${main_domain}', 'test.booqy.se')
    .replaceAll('${dev_domain}', 'test-dev.booqy.se')
    .replace("import cf from 'cloudfront';", '');
  assert.ok(!source.includes('${'), 'every template value is filled in');
  const cf = {
    kvs(id) {
      assert.equal(id, 'kvs-test');
      return {
        async get(key) {
          if (!(key in keys)) throw new Error('KeyNotFound');
          return keys[key];
        }
      };
    }
  };
  return new Function('cf', source + '\nreturn handler;')(cf);
}

const KEYS = { pasta: 't-pasta', 'example-se': 't-pasta', roma: 't-roma' };
const handler = load(KEYS);

function event(host, uri) {
  return { request: { method: 'GET', uri, headers: host === null ? {} : { host: { value: host } } } };
}

async function uri(host, path) {
  const out = await handler(event(host, path));
  assert.equal(out.statusCode, undefined, `${host}${path} is passed on, not answered`);
  return out.uri;
}

test('main and dev hosts go to their own stage folder of the tenant', async () => {
  assert.equal(await uri('pasta.test.booqy.se', '/assets/index-abc.js'), '/main/sites/t-pasta/assets/index-abc.js');
  assert.equal(await uri('pasta.test-dev.booqy.se', '/assets/index-abc.js'), '/dev/sites/t-pasta/assets/index-abc.js');
  assert.equal(await uri('roma.test.booqy.se', '/favicon.svg'), '/main/sites/t-roma/favicon.svg');
});

test('a mapped own domain is just another label for the same tenant', async () => {
  assert.equal(await uri('example-se.test.booqy.se', '/'), '/main/sites/t-pasta/index.html');
  assert.equal(await uri('example-se.test-dev.booqy.se', '/'), '/dev/sites/t-pasta/index.html');
});

test('client-side routes load index.html (SPA fallback)', async () => {
  for (const path of ['/', '/meny', '/boka/bord', '/om-oss/', '/a/../../x']) {
    assert.equal(await uri('pasta.test.booqy.se', path), '/main/sites/t-pasta/index.html', path);
  }
  assert.equal(await uri('pasta.test.booqy.se', '/sitemap.xml'), '/main/sites/t-pasta/sitemap.xml');
});

test('host casing and a port do not matter', async () => {
  assert.equal(await uri('Pasta.TEST.booqy.se:443', '/'), '/main/sites/t-pasta/index.html');
});

test('robots.txt is always the sandbox one (Disallow)', async () => {
  assert.equal(await uri('pasta.test.booqy.se', '/robots.txt'), '/_platform/robots.txt');
  assert.equal(await uri('pasta.test-dev.booqy.se', '/robots.txt'), '/_platform/robots.txt');
});

test('an unknown or foreign host gets the 404 page, never another site', async () => {
  for (const host of ['nobody.test.booqy.se', 'test.booqy.se', 'a.b.test.booqy.se', 'pasta.dev.booqy.se',
                      'pasta.booqy.se', 'pasta.test.booqy.se.evil.com', '-x.test.booqy.se', '', null]) {
    const out = await handler(event(host, '/'));
    assert.equal(out.statusCode, 404, String(host));
    assert.equal(out.headers['x-robots-tag'].value, 'noindex, nofollow');
    assert.match(out.body.data, /Sidan finns inte/);
  }
});

test('a value in the store that is not a tenant folder is refused', async () => {
  const bad = load({ evil: '../../main/sites/t-roma', empty: '' });
  assert.equal((await bad(event('evil.test.booqy.se', '/'))).statusCode, 404);
  assert.equal((await bad(event('empty.test.booqy.se', '/'))).statusCode, 404);
});
