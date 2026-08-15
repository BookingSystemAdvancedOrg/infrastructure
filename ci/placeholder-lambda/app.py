"""
Placeholder Lambda handler.

This image is pushed by CI (reusable_cicd.yml, "Push placeholder image to
any empty ECR repository" step) into any function's ECR repository that
doesn't have a ":latest" image yet - purely so `aws_lambda_function` with
package_type = "Image" has something valid to reference the first time
Terraform creates that function. It is never pushed to a repository that
already has a real image, so this should never run in an environment with
real application code deployed.

If you see this response, the real application image for this function
has not been deployed yet.
"""


def handler(event, context):
    return {
        "statusCode": 501,
        "body": "placeholder image - real application code has not been deployed to this function yet",
    }
