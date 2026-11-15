# Own domains (owner 2026-11-15): once a restaurant's own domain is live,
# guests only ever see it. The slug address (<slug>.booqy.se, dev
# <slug>.dev.booqy.se) and www.<domain> answer with a 301 to the canonical
# host, path and query kept. A CloudFront Function on the multi-tenant
# distribution's default behaviour looks the viewer's host up in this key
# value store (host -> canonical host). platform-tenants writes and deletes
# the keys (SetCanonical in domain-provision, domain removal, offboarding);
# an empty store changes nothing. Tenant parameters can't be read from a
# function and Lambda@Edge doesn't run on multi-tenant distributions, so
# this is the one place a real 301 can come from.
# Cost: $0.10 per million function runs + $0.03 per million store reads.
resource "aws_cloudfront_key_value_store" "site_redirects" {
  count = local.tenant_sites_count

  name    = "${local.prefix}site-redirects"
  comment = "Restaurant sites: old host -> live own domain (301), written by platform-tenants"
}

resource "aws_cloudfront_function" "site_redirect" {
  count = local.tenant_sites_count

  name    = "${local.prefix}site-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "Restaurant sites: 301 from the slug address and www to the live own domain"
  publish = true
  code = templatefile("${path.module}/function/site-redirect.js", {
    # The store's ID (cf.kvs() needs it), the last part of its ARN
    kvs_id = element(split("/", aws_cloudfront_key_value_store.site_redirects[0].arn), 1)
  })
  key_value_store_associations = [aws_cloudfront_key_value_store.site_redirects[0].arn]
}
