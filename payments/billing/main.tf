# The subscription catalog in YOUR platform Stripe account, as code: one
# product and one monthly price per plan in var.plans, plus the Swedish VAT
# rate every subscription invoice carries. The price ids are written into
# the PLAN# rows of the tenant table (storage/dynamodb/tenant), which is
# where Booqy Console reads them when it starts or changes a customer's
# subscription - the console never needs to know a Stripe id at build time.
#
# Prices are immutable in Stripe: changing price_sek creates a new price
# and archives the old one (active = false; Stripe cannot delete a price).
# Subscriptions on the old price keep running until the customer's plan is
# saved again in Booqy Console, which moves them to the current price.
#
# The restaurants' own Connect accounts (guest payments) have nothing to do
# with this module.
terraform {
  required_providers {
    stripe = {
      source = "lukasaron/stripe"
    }
  }
}

locals {
  prefix = var.environment == "prod" ? "" : "${var.environment} "
}

resource "stripe_product" "plan" {
  for_each = var.plans

  name        = "${local.prefix}Booqy ${each.value.name}"
  description = "Booqy ${each.value.name}: table booking, online ordering and the restaurant site, ${each.value.max_locations} location(s)"
  metadata = {
    planId      = each.key
    environment = var.environment
  }
}

resource "stripe_price" "plan" {
  for_each = var.plans

  product      = stripe_product.plan[each.key].id
  currency     = "sek"
  unit_amount  = each.value.price_sek * 100
  tax_behavior = "exclusive"
  nickname     = "${each.value.name} monthly"
  metadata = {
    planId      = each.key
    environment = var.environment
  }

  recurring {
    interval       = "month"
    interval_count = 1
    usage_type     = "licensed"
  }

  # A new amount = a new price; the old one is archived after the new one
  # exists, so the PLAN# rows never point at a price that is gone.
  lifecycle {
    create_before_destroy = true
  }
}

# Swedish VAT on the SaaS subscription. Added to the price (exclusive):
# the invoice shows the plan price, Moms 25 % and the total. All customers
# are Swedish companies, so one fixed rate is right and Stripe Tax (0.5 %
# per transaction) is not needed.
resource "stripe_tax_rate" "vat" {
  display_name = "Moms"
  description  = "Mervärdesskatt 25 %"
  jurisdiction = "SE"
  country      = "SE"
  percentage   = 25
  inclusive    = false
  tax_type     = "vat"
  metadata = {
    environment = var.environment
  }
}
