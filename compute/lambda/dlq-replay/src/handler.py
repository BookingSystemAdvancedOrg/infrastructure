"""DlqReplayFn - drains the platform's three dead-letter queues.

Invoked only by the recurring EventBridge schedule (compute/lambda/dlq-replay),
with {"queue": "all" | "lifecycle_stream" | "notification_stream" | "scheduled_invocation",
      "max": 50}.

For every message it redelivers the failed work to the Lambda that owns it
and deletes the message only once that Lambda succeeded:

  lifecycle_stream      pointer to failed catering-requests stream records
                        -> re-read them, invoke catering-lifecycle with {"Records": [...]}
  notification_stream   pointer to failed records from the reservation, order
                        or catering-requests stream -> re-read them, invoke
                        NotificationFn with {"Records": [...]}
  scheduled_invocation  a failed scheduled (asynchronous) run:
                          - Lambda async on-failure record (Terraform-configured on
                            catering-lifecycle, no-show-check, reactivate-menu-item,
                            expire-layout-version): target = requestContext.functionArn,
                            payload = requestPayload
                          - EventBridge Scheduler DLQ message (catering-lifecycle sets
                            DeadLetterConfig on its schedules): payload = body,
                            target = TARGET_ARN message attribute
                        -> invoke the target with the original payload, but only if
                           it's in REPLAYABLE_FUNCTION_ARNS

It never does business work itself; the owning Lambdas are idempotent
(conditional writes, deterministic schedule names, audit keys with
attribute_not_exists), which is what makes redelivery safe.

Outcomes per message:
  success                       -> deleted
  failure                       -> left in the queue; retried next run
  ApproximateReceiveCount > MAX -> escalated once to SNS, then parked (hidden
                                   12h at a time) until it expires after 14 days
                                   or someone handles it
  stream records expired (>23h) -> lifecycle_stream: catering-lifecycle is asked
                                   to reconcile from the table, then deleted;
                                   notification_stream: escalated (a message to
                                   a customer/owner may be missing), then deleted
  unknown / not-allow-listed    -> escalated, then deleted

Reference implementation - build and push it from the backend repo like the
other functions (this repo's CI only pushes a placeholder image).
"""

import base64
import datetime as dt
import json
import logging
import os

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

sqs = boto3.client("sqs")
lam = boto3.client("lambda")
streams = boto3.client("dynamodbstreams")
sns = boto3.client("sns")

QUEUES = {
    "lifecycle_stream": os.environ["LIFECYCLE_STREAM_DLQ_URL"],
    "notification_stream": os.environ["NOTIFICATION_STREAM_DLQ_URL"],
    "scheduled_invocation": os.environ["SCHEDULED_INVOCATION_DLQ_URL"],
}
LIFECYCLE_ARN = os.environ["CATERING_LIFECYCLE_FUNCTION_ARN"]
STREAM_TARGETS = {
    "lifecycle_stream": LIFECYCLE_ARN,
    "notification_stream": os.environ["NOTIFICATION_FUNCTION_ARN"],
}
REPLAYABLE = set(json.loads(os.environ["REPLAYABLE_FUNCTION_ARNS"]))
ALERT_TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]
MAX_ATTEMPTS = int(os.environ.get("MAX_REPLAY_ATTEMPTS", "3"))
STREAM_RETENTION = dt.timedelta(hours=int(os.environ.get("STREAM_RETENTION_HOURS", "23")))
ENVIRONMENT = os.environ.get("ENVIRONMENT", "")

VISIBILITY_SECONDS = 330           # > this function's 300s timeout: no overlap
PARK_SECONDS = 12 * 60 * 60        # SQS maximum visibility timeout
SAFETY_MARGIN_MS = 30_000          # stop pulling new messages near the timeout


class ReplayFailed(Exception):
    pass


class Unreplayable(Exception):
    """Can never succeed by retrying - escalate and drop."""


def handler(event, context):
    which = event.get("queue", "all")
    budget = int(event.get("max", 50))
    names = list(QUEUES) if which == "all" else [which]
    stats = {"replayed": 0, "reconciled": 0, "left_for_next_run": 0, "escalated": 0, "parked": 0}

    for name in names:
        while budget > 0 and context.get_remaining_time_in_millis() > SAFETY_MARGIN_MS:
            resp = sqs.receive_message(
                QueueUrl=QUEUES[name],
                MaxNumberOfMessages=min(10, budget),
                VisibilityTimeout=VISIBILITY_SECONDS,
                WaitTimeSeconds=1,
                AttributeNames=["ApproximateReceiveCount", "SentTimestamp"],
                MessageAttributeNames=["All"],
            )
            messages = resp.get("Messages", [])
            if not messages:
                break
            budget -= len(messages)
            for m in messages:
                stats[process(name, m)] += 1

    log.info("dlq-replay summary %s", json.dumps(stats))
    return stats


def process(name, m):
    url, receipt = QUEUES[name], m["ReceiptHandle"]
    attempts = int(m["Attributes"]["ApproximateReceiveCount"])

    if attempts > MAX_ATTEMPTS:
        if attempts == MAX_ATTEMPTS + 1:
            alert(f"{name}: gave up after {MAX_ATTEMPTS} replays",
                  {"queue": name, "messageId": m["MessageId"], "body": m["Body"]})
            outcome = "escalated"
        else:
            outcome = "parked"
        sqs.change_message_visibility(QueueUrl=url, ReceiptHandle=receipt, VisibilityTimeout=PARK_SECONDS)
        return outcome

    try:
        body = json.loads(m["Body"])
        if name == "scheduled_invocation":
            target, payload = scheduled_target(body, m.get("MessageAttributes", {}))
            invoke(target, payload)
            outcome = "replayed"
        else:
            info = body["DDBStreamBatchInfo"]
            first = dt.datetime.fromisoformat(info["approximateArrivalOfFirstRecord"].replace("Z", "+00:00"))
            if dt.datetime.now(dt.timezone.utc) - first > STREAM_RETENTION:
                outcome = handle_expired(name, info)
            else:
                invoke(STREAM_TARGETS[name], {"Records": read_records(info)})
                outcome = "replayed"
    except Unreplayable as exc:
        alert(f"{name}: message can't be replayed - {exc}",
              {"queue": name, "messageId": m["MessageId"], "body": m["Body"]})
        outcome = "escalated"
    except Exception as exc:  # noqa: BLE001 - every other failure means "try again next run"
        log.warning("replay of %s message %s failed (attempt %d): %s", name, m["MessageId"], attempts, exc)
        return "left_for_next_run"

    sqs.delete_message(QueueUrl=url, ReceiptHandle=receipt)
    return outcome


def scheduled_target(body, attrs):
    """Works out which function to redeliver to, and with what payload."""
    if isinstance(body, dict) and "requestContext" in body and "requestPayload" in body:
        # Lambda async on-failure record.
        target = unqualified(body["requestContext"]["functionArn"])
        payload = body["requestPayload"]
    else:
        # EventBridge Scheduler DeadLetterConfig message: body is the schedule input.
        target_attr = attrs.get("TARGET_ARN", {}).get("StringValue")
        target = unqualified(target_attr) if target_attr else LIFECYCLE_ARN
        payload = body
    if target not in REPLAYABLE:
        raise Unreplayable(f"target {target} is not on the replay allow-list")
    return target, payload


def unqualified(arn):
    # arn:aws:lambda:region:acct:function:name[:qualifier] -> without qualifier
    parts = arn.split(":")
    return ":".join(parts[:7])


def handle_expired(name, info):
    window = {k: info.get(k) for k in ("streamArn", "approximateArrivalOfFirstRecord", "approximateArrivalOfLastRecord", "batchSize")}
    if name == "lifecycle_stream":
        # catering-lifecycle re-checks every open request from the table:
        # timers present, invoice issued, expiries applied.
        invoke(LIFECYCLE_ARN, {"action": "reconcile", "source": "dlq-replay", "window": window})
        return "reconciled"
    # A notification record can't be rebuilt once the stream dropped it.
    alert("notification_stream: records expired before replay - a notification in this window may be missing", window)
    return "escalated"


def read_records(info):
    """Re-reads the failed batch from the stream, in Lambda's event shape."""
    end = int(info["endSequenceNumber"])
    iterator = streams.get_shard_iterator(
        StreamArn=info["streamArn"],
        ShardId=info["shardId"],
        ShardIteratorType="AT_SEQUENCE_NUMBER",
        SequenceNumber=info["startSequenceNumber"],
    )["ShardIterator"]

    records = []
    while iterator:
        page = streams.get_records(ShardIterator=iterator, Limit=100)
        for r in page["Records"]:
            if int(r["dynamodb"]["SequenceNumber"]) > end:
                return records
            r["eventSourceARN"] = info["streamArn"]
            records.append(r)
        if not page["Records"]:
            break
        iterator = page.get("NextShardIterator")
    if not records:
        raise ReplayFailed("no records found for the failed batch")
    return records


def invoke(function_arn, payload):
    resp = lam.invoke(FunctionName=function_arn, Payload=json.dumps(payload, default=_json_default).encode())
    result = resp["Payload"].read().decode() or "null"
    if "FunctionError" in resp:
        raise ReplayFailed(f"{function_arn} errored: {result[:500]}")
    parsed = json.loads(result)
    # Stream handlers with ReportBatchItemFailures signal partial failure this way.
    if isinstance(parsed, dict) and parsed.get("batchItemFailures"):
        raise ReplayFailed(f"{function_arn} reported failed items: {parsed['batchItemFailures']}")


def alert(subject, detail):
    sns.publish(
        TopicArn=ALERT_TOPIC_ARN,
        Subject=f"[{ENVIRONMENT}] {subject}"[:100],
        Message=json.dumps(detail, indent=2, default=_json_default),
    )


def _json_default(value):
    if isinstance(value, dt.datetime):
        return value.timestamp()          # Lambda's stream events use epoch seconds
    if isinstance(value, (bytes, bytearray)):
        return base64.b64encode(value).decode()
    if isinstance(value, set):
        return list(value)
    raise TypeError(f"not serializable: {type(value)}")
