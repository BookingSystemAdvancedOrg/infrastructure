output "price_ids" {
  description = "Stripe price id (price_...) per plan id - written into the PLAN# rows"
  value       = { for k, p in stripe_price.plan : k => p.id }
}

output "tax_rate_id" {
  description = "Stripe tax rate id (txr_...) of the Swedish VAT rate every subscription carries"
  value       = stripe_tax_rate.vat.id
}
