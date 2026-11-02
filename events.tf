# Feature event bus (events/): <prefix>booqy-events. Producer and consumer
# IAM and rules live in each feature's own module.
module "events" {
  source      = "./events"
  environment = var.env
}
