// Restaurant sites, viewer request (cloudfront-js-2.0) on the multi-tenant
// distribution. Terraform template: kvs_id is filled in by
// network/platform-domain/redirects.tf.
//
// Once a restaurant's own domain is live, guests only ever see it: the old
// addresses answer with a permanent redirect to it, path and query kept.
// The key value store maps a host to the canonical host, written by
// platform-tenants (the domain-provision workflow's SetCanonical step) and
// removed when the domain is removed or the restaurant offboarded:
//
//   <slug>.booqy.se      -> example.se      (prod)
//   www.example.se       -> example.se      (prod, Booqy runs the DNS)
//   <slug>.dev.booqy.se  -> dev.example.se  (dev)
//
// A host that is not in the store, a store error, or a value that is not a
// plain host name: the request goes on unchanged (fail open, the site keeps
// answering on that host). /.well-known/ is never redirected (certificate
// validation).
import cf from 'cloudfront';

const kvs = cf.kvs('${kvs_id}');
const HOST = /^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/;

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

async function handler(event) {
  const request = event.request;
  const header = request.headers.host;
  const host = (header && header.value ? header.value : '').toLowerCase().split(':')[0];
  if (!HOST.test(host) || request.uri.indexOf('/.well-known/') === 0) {
    return request;
  }
  let target;
  try {
    target = await kvs.get(host);
  } catch (e) {
    return request;
  }
  if (typeof target !== 'string') {
    return request;
  }
  target = target.toLowerCase();
  if (!HOST.test(target) || target === host) {
    return request;
  }
  const qs = query(request.querystring);
  return {
    statusCode: 301,
    statusDescription: 'Moved Permanently',
    headers: {
      location: { value: 'https://' + target + request.uri + (qs ? '?' + qs : '') },
      'cache-control': { value: 'max-age=3600' }
    }
  };
}
