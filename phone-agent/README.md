# phone-agent

AI phone agent: answers the restaurant's phone, books, moves and cancels on Booqy's rules, hands over to staff or takes a callback (feature phoneAgent).

- Decision record: `docs/adr/ADR-L-phone-agent.md`; contract: `docs/build/CONTRACTS.md`
  (feature L, sections 0, 4, 5, 6.L, 9, 11, 12 and 13).
- Built in Run 2. No resources until Run 2: the Run 0 addendum instantiates the
  module (`phone-agent.tf`) with only `environment` and the empty `wiring` output.
- Routes: `network/api-gateway/phone-agent-routes.tf` (`local.phone_agent_routes`).
- ECR repositories already exist (`module "phone_agent_ecr"`, `module "phone_agent_call_ecr"` and `module "phone_agent_jobs_ecr"` in `config.tf`).
