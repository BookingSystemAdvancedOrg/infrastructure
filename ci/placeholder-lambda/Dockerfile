# Placeholder Lambda container image - see app.py for why this exists.
# Not meant to match any real function's runtime/dependencies; only used
# to give a brand-new ECR repository a valid ":latest" image so Terraform
# can create the Lambda function that references it for the first time.
FROM public.ecr.aws/lambda/python:3.13

COPY app.py ${LAMBDA_TASK_ROOT}

CMD ["app.handler"]
