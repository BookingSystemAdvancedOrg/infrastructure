output "price_ids" {
  description = "Stripe price id (price_...) per plan id - written into the PLAN# rows"
  value       = { for k, p in stripe_price.plan : k => p.id }
}

output "tax_rate_id" {
  description = "Stripe tax rate id (txr_...) of the Swedish VAT rate every subscription carries"
  value       = stripe_tax_rate.vat.id
}

output "product_ids" {
  description = "Stripe product id (prod_...) per plan id - a customer's own price is created on the plan's product"
  value       = { for k, p in stripe_product.plan : k => p.id }
}
