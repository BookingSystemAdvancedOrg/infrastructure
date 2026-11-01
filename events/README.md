# events

The custom EventBridge bus `<prefix>booqy-events` (Run 0). Features publish
domain events to it with source `booqy.<feature-id>` through application
`shared/events.py`; the detail types and fields are in
`docs/build/CONTRACTS.md` section 5 (source of truth:
`application/contracts/booqy.yaml`).

- Producers: `events:PutEvents` on `bus_arn` with condition
  `events:source = booqy.<feature-id>`, in the producer's own module.
- Consumers: their own `aws_cloudwatch_event_rule` on `bus_name` and an SQS
  DLQ, in the consumer's own module. Every consumer is idempotent (delivery is
  at least once).

Outputs: `bus_name`, `bus_arn`.
