# Placeholder Lambda container image - see app.py for why this exists.
# Not meant to match any real function's runtime/dependencies; only used
# to give a brand-new ECR repository a valid ":latest" image so Terraform
# can create the Lambda function that references it for the first time.
# Every Booqy Lambda runs on arm64 (architectures = ["arm64"]). An image built
# for the runner's amd64 made a new function fail with Runtime.InvalidEntrypoint
# until its real image arrived (google-business-jobs alarm, 2026-11-15). The
# build only copies a file (no RUN), so it needs no emulation on an amd64 runner.
FROM --platform=linux/arm64 public.ecr.aws/lambda/python:3.13

COPY app.py ${LAMBDA_TASK_ROOT}

CMD ["app.handler"]
