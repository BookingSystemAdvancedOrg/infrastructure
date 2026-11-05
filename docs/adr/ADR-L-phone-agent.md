# ADR-L: AI phone booking agent (answers the phone, books on Booqy's rules)

**Status:** Proposed
**Date:** 2026-11-02
**Deciders:** Owner (product, pricing, provider contracts), orchestrator (contracts); **lawyer** (EU AI Act art. 50 wording, recording notice, DPAs with the voice and SIP providers); **accountant** (VAT on the per-minute fee)
**Run:** scaffolded in the Run 0 addendum, built in Run 2 against this contract; voice QA with real calls in Run 3

Fixed decisions from `docs/build/PROMPTS.md` ADDENDUM A are not re-opened
here; this ADR fills in how they are built. Anything marked
**[NEEDS YOUR OK]** is a proposal for the owner, not a decision.

## Context

A restaurant misses calls during service and after closing. Guests who
cannot get through book elsewhere. Booqy already has everything a booking
call needs: availability (`get-availability`, `GET /locations/{l}/availability`),
holds and pending reservations with double-booking protection
(`create-pending-reservation`, `POST .../holds`, `POST .../reservations`),
changes and arrivals (`mark-arrived`, `PATCH .../reservations/{id}`),
cancellation (`cancel-reservation`), the menu (`get-menu`), hours, special
days and policies (`tenant-site-config`), SMS through `notification`
(prefixes, part counting, dev outbox) and the card guarantee flow completed
by the guest on a link (`docs/RESERVATION-PAYMENT-FLOW.md`). It has no
telephony, no speech and no LLM agent loop. Run 0 built the external client
pattern (port, simulator, factory from one env var, simulator refused in
prod), the event bus, feature hooks and a `TextModel` port for Bedrock
(`shared/bedrock.py`, owned by A).

Fixed: the agent is a channel into the existing booking engine, the brain is
Claude on Bedrock in eu-north-1, speech is abstracted behind a provider
interface, telephony behind another, art. 50 disclosure is non-negotiable,
transcripts by default and audio off by default, handoff with a 25 s
transfer then callback, caps and a kill switch, entitlement off by default,
Swedish first and English second.

## Decision

1. **Three Lambdas, one table.** `phone-agent` (JWT and operator routes,
   hooks, number provisioning, config), `phone-agent-call` (the real-time
   side: provider webhooks, the agent turn endpoint, tool execution,
   call-end processing) and `phone-agent-jobs` (nightly retention and
   stuck-call sweep, period rollups). The real-time Lambda is separate so its
   memory, concurrency reservation and timeout can be tuned for latency
   without touching the admin API.

2. **The brain is a Booqy-side agent loop on Bedrock.** Every assistant turn
   is produced by `shared/features/phone_agent/agent.py`: it builds the
   system prompt from the location's config and `/site-config`, sends the
   conversation so far plus the tool schemas to Claude through a new port
   `AgentModel.converse(system, messages, tools) -> Turn{text?, tool_uses[]}`
   (`shared/agent_model.py`, simulator + real; not A's `TextModel`, which is
   a single-shot completion port), executes tool calls inside Booqy, feeds
   the results back, and returns the final text. The voice provider never
   sees a tool definition, a tool result or tenant data; it sees audio, the
   transcript so far and the agent's spoken text. Model id from Terraform
   `phone_agent_model_id` (a fast model; the Run 2 builder measures first-token
   latency against the budget in section "Latency budget" and the owner
   picks the model in `dev.tfvars`); `bedrock:InvokeModelWithResponseStream`
   only on that model or EU inference profile ARN.

3. **Voice provider abstraction (`shared/voice_provider.py`).** One port
   `VoiceProvider` with these methods:

   | Method | Purpose |
   |---|---|
   | `create_agent(config: AgentVoiceConfig) -> provider_agent_id` | one provider-side agent per location (voice, language set, greeting text, barge-in on, our LLM endpoint URL and its secret header, our events webhook); idempotent by `name = "<prefix>phone-agent-<locationId>"` |
   | `update_agent(provider_agent_id, config)` | after the wizard saves |
   | `delete_agent(provider_agent_id)` | on disable and purge |
   | `sip_target(provider_agent_id) -> SipTarget{uri, auth?}` | where the telephony provider forwards the call |
   | `say(call_ref, text)` | inject speech outside the LLM turn (disclosure repeat, "jag kopplar dig nu", resume after a failed transfer) |
   | `transfer(call_ref, to_e164, timeout_s) -> TransferResult{answered: bool}` | attended transfer with timeout, via the provider's SIP REFER or the telephony provider (section "Handoff") |
   | `end(call_ref, reason)` | hang up |
   | `recording_url(call_ref) -> url \| None` | only when the tenant opted in; fetched once and copied to our bucket |
   | `parse_webhook(headers, body) -> list[VoiceEvent]` | verifies the signature (secret `${prefix}phone-agent/voice-provider`), returns typed events: `call_started{call_ref, provider_agent_id, from, to}`, `transcript{role, text, at, final}`, `language_detected{lang}`, `interrupted{at}` (barge-in during agent speech), `transfer_result`, `call_ended{at, reason, usage{seconds}}` |

   The agent turn endpoint is an OpenAI-compatible chat-completions SSE
   stream (`POST /v1/chat/completions`) served by `phone-agent-call` behind a
   **Lambda Function URL** with response streaming (Lambda Web Adapter in the
   image), protected by a per-environment random secret header
   (`${prefix}phone-agent/llm-endpoint-key`) plus the call's own id in the
   provider's metadata; the Lambda maps the provider's `call_ref` to our
   `callId` (table row written at `call_started`) and refuses unknown or
   ended calls. Streaming matters only for time-to-first-word; the
   simulator and unit tests call the same function without SSE.

   **Launch provider: ElevenLabs Agents Platform over SIP trunk, with its
   "custom LLM" option pointed at our endpoint [NEEDS YOUR OK: account,
   contract, DPA, EU data residency setting].** Criteria that decided it
   against OpenAI gpt-realtime over SIP: (a) it lets Claude on Bedrock
   generate every turn (gpt-realtime is speech-to-speech and would make
   OpenAI the brain, against the fixed decision); (b) Swedish ASR and
   Swedish TTS voices, auto language detection per call; (c) SIP trunk
   inbound, barge-in and turn-taking handled provider-side; (d) per-minute
   pricing, no monthly minimum at launch volume [NEEDS YOUR OK: price].
   OpenAI Realtime stays documented as the second real adapter
   (`shared/voice_provider_openai.py`, not built) for the case ElevenLabs
   fails voice QA in Run 3: it would run in transcription mode (our turn
   text synthesised by a TTS call), which is the AWS fallback shape below
   with another vendor.

   **AWS fallback pipeline (documented, not built in Run 2):** Amazon
   Connect or the SIP provider's media stream -> Amazon Transcribe streaming
   `sv-SE` / `en-US` with partial results and end-pointing -> the same agent
   loop -> Amazon Polly neural `sv-SE` / `en-GB` -> back on the call. Same
   `VoiceProvider` port, one more real adapter (`shared/voice_provider_aws.py`).
   Latency is worse (no streamed duplex) and barge-in must be built by us,
   which is why it is the fallback. **Re-check Amazon Nova Sonic's language
   list every quarter** (owner's calendar; STATUS.md "Human actions"): when
   it gains Swedish it becomes the preferred all-AWS adapter.

4. **Telephony abstraction (`shared/telephony.py`).** Port `Telephony`:

   | Method | Purpose |
   |---|---|
   | `provision_number(country="SE", label) -> Number{e164, provider_id}` | one Swedish number per enabled location |
   | `release_number(provider_id)` | on disable (after 30 days grace, see section "Data model") and purge |
   | `set_inbound(provider_id, sip: SipTarget, fallback_e164)` | inbound calls go to the voice provider's SIP target; if that fails (SIP error, timeout), ring `fallback_e164` (the restaurant's phone), so a Booqy outage never means a dead number |
   | `transfer(call_ref, to_e164, timeout_s) -> TransferResult` | used when the voice provider cannot do the transfer itself |
   | `parse_webhook(headers, body) -> list[TelephonyEvent]` | `inbound{call_ref, from, to, at}`, `ended{call_ref, duration_s, cause}`; signature or Basic-auth check |
   | `verify_forwarding(e164) -> ForwardingCheck` | optional: a test call that reads a code, for the wizard's "Testa vidarekoppling" step (v1 may return `unsupported`) |

   **Decision: 46elks for launch, Twilio documented as the alternative
   [NEEDS YOUR OK: account and Swedish numbers].** Criteria:

   | Criterion | 46elks | Twilio |
   |---|---|---|
   | Swedish numbers, KYC for a Swedish company | native, same day | available, address verification per number |
   | Forward inbound to a SIP URI | `connect` to `sip:` (verify in sandbox week 1 of Run 2) | Elastic SIP Trunking, mature |
   | Data residency and DPA | Swedish company, EU hosting, Swedish DPA | US company, EU region selectable, SCCs |
   | Pricing | SEK, per minute, no minimum | USD, per minute |
   | Webhook auth | Basic auth / IP list | HMAC signature |
   | Support and docs in Swedish | yes | no |

   Exit condition: if the sandbox test shows 46elks cannot forward an
   inbound call to the voice provider's SIP target with a fallback number,
   the Run 2 builder switches `shared/telephony_real.py` to Twilio before
   building anything else and reports it. Porting the restaurant's own
   number is out of scope: the restaurant forwards its number to the Booqy
   number (no answer after N seconds, or always outside hours) using its
   operator's forwarding codes, which the wizard shows per operator (Telia,
   Tele2, Telenor, Tre) [NEEDS YOUR OK: codes verified by a human].

5. **Call lifecycle: in-Lambda state on the call row, not Step Functions.**
   A call is driven by provider webhooks and the streamed turn endpoint at
   sub-second cadence; a Step Functions transition per turn would add
   latency and cost for no durability we do not already have in DynamoDB.
   The `CALL#` item carries `status` and every transition is a conditional
   update (`status = :from`), so a duplicate webhook is a no-op.

   ```
   ringing -> answered -> disclosed -> talking -> {transferring -> talking | ended}
                                        talking -> ended
   any     -> ended (hangup, max length, kill switch, provider error)
   ended   -> processed (minutes metered, transcript sealed, callback created,
                         events published, recording copied or discarded)
   ```

   Guards before `answered`: tenant active, `phoneAgent` on, location
   enabled, kill switch off (location, tenant pause, platform), inside agent
   hours (or mode `always`), minutes cap not reached. A refused call is
   answered with a fixed Swedish/English sentence ("Tyvärr kan vi inte ta
   emot bokningar per telefon just nu, besök vår hemsida") and ended
   (`outcome: refused`, 0 billed minutes, counted in the calls list so the
   owner sees it). `max_call_seconds` (default 480, 120-900) is enforced by
   the provider's max duration and by the sweep in `phone-agent-jobs`
   (every 5 minutes: any call `talking` longer than max + 60 s is ended and
   processed). `processed` is idempotent and re-runnable: the sweep also
   picks up `ended` calls older than 2 minutes.

6. **Art. 50 disclosure, by construction.** The greeting is assembled by
   Booqy, not typed freely: `"<Hej|Hello>, du pratar med <agentName>, en
   AI-assistent för <restaurant>. ..."`; the owner edits only the part after
   the disclosure. The first utterance is played with `say()` before the
   LLM gets a turn, and `disclosed` is set when the provider's transcript
   event for it arrives (`disclosure.playedAt`). If an `interrupted` event
   arrives before the disclosure sentence is complete, the agent says the
   short form again ("Jag är en AI-assistent för <restaurant>.") and counts
   it (`disclosure.repeats`). If the caller switches language, the short form
   is said once in the new language (`disclosure.languages[]`). The system
   prompt forbids claiming to be human and instructs the agent to confirm it
   is an AI when asked. **Evidence:** every call row stores
   `disclosure{text, playedAt, repeats, languages[]}` and the transcript's
   first agent turn is the disclosure; the test plan requires it in every
   scenario including interruption. The wording is **[NEEDS YOUR OK:
   lawyer]** and lives in `shared/features/phone_agent/copy.py` as a
   constant, never in the owner-editable text.

7. **Recording and transcripts.** Transcripts always (they are the booking
   evidence and the owner's view); audio off by default. Owner opt-in per
   tenant in the wizard with a required purpose text and a retention of 7,
   30 or 90 days **[NEEDS YOUR OK: options and default 30]**; with recording
   on, the greeting adds "Samtalet spelas in" before the disclosure sentence
   and the transcript records it. Audio is copied once from the provider
   into `<prefix>phone-agent-recordings-<account>` (private, SSE, lifecycle
   by prefix `<tenantId>/<retention>/`, no public access) and deleted at the
   provider (provider setting "no retention" **[NEEDS YOUR OK: confirm in
   the provider contract]**). Owners stream it from admin through a presigned
   URL (5 minutes); staff never. Transcript turns have `ttl` of 24 months
   after the call (same as the booking contact rule) **[NEEDS YOUR OK]**;
   the call row stays 7 years with contact fields removed (minutes are a
   billing record) like gift card TX rows.

8. **Handoff and callback.** Intents in both languages ("prata med en
   människa", "kan jag få prata med någon", "speak to a person", "a human
   please", plus the agent's own judgement when it cannot resolve) call tool
   `transfer_to_staff`. The agent says "Jag kopplar dig till restaurangen,
   ett ögonblick", status `transferring`, `transfer(call_ref, transferTo,
   25)`. Answered: the call leaves the agent, `outcome: transferred`,
   minutes stop at the transfer. Not answered in 25 s: the agent resumes
   ("Ingen kunde svara just nu. Vill du att de ringer upp dig?"), takes name,
   number (caller id by default) and topic with `request_callback`, which
   writes a `CALLBACK#` row and shows up in Bokningar (slot
   `bokningar.panel.callbacks`) with the call summary; staff close it with
   one tap. Anything the agent cannot do (party over the online limit when
   the guarantee cannot be sent, special requests, complaints, large groups,
   catering) ends the same way. No payments and no card data over the phone:
   when the booking needs a card guarantee the agent creates the pending
   reservation and sends the existing payment link by SMS
   (`notification` kind `phone-agent.guarantee-link`), says that the table
   is held until the link is used (the existing hold time), and the booking
   confirms through the existing payment flow.

9. **Caps, alarms, kill switches.** Per tenant `minutesCapPerMonth` (owner,
   default = the plan's included minutes, at most the platform ceiling from
   the console) checked at `ringing`; 80 % emails the owner once per period
   (`notification` kind `phone-agent.cap-warning`), 100 % refuses new calls
   (`outcome: refused`, reason `cap`) and publishes `PhoneMinutes.CapReached`.
   Kill switch per location (owner and staff, one tap on the Telefon page
   and in the Bokningar panel), per tenant pause (operator), platform-wide
   (`PLATFORM#PHONE_AGENT/SETTINGS` in the tenant table, like meta ads).
   CloudWatch: custom metrics `Booqy/PhoneAgent` `CallsAnswered`,
   `CallsRefused`, `BilledMinutes`, `TurnLatencyMs` (p95), `ProviderErrors`;
   alarms to the ops topic on `BilledMinutes` per day above a platform
   threshold (Terraform `phone_agent_daily_minutes_alarm`, default 600
   **[NEEDS YOUR OK]**), on `ProviderErrors` > 5 in 5 minutes, on
   `TurnLatencyMs` p95 > 2 500 ms for 15 minutes, and the module's Errors
   alarms. Spend alarm on the provider side is a human setting (provider
   dashboards) listed under human actions.

10. **Minutes metering for billing.** At `processed`, `billedMinutes =
    ceil((min(endedAt, transferAnsweredAt) - answeredAt) / 60)` (refused and
    unanswered calls are 0). The row `USAGE#<periodEnd>` (billing period
    25th-24th, `shared/finance.billing_day` imported read-only) gets `ADD
    minutes :m` and `ADD loc.<l> :m`, conditional on the call not yet
    metered (`metered = false`). Invoicing: platform-tenants' invoicing run
    calls the new hook `billing.usage` (`periodStart`, `periodEnd`) and the
    feature answers `lines[{locationId, minutes}]`; the run adds two invoice
    lines per period: "Telefonassistent, <n> platser" at
    `phone_agent_location_price_sek` and "Telefonminuter utöver
    <included>: <m> x <price>" at `phone_agent_minute_price_sek`, idempotent
    like the SMS line (`phone-<tenant>-<periodEnd>`). Prices and included
    minutes are **[NEEDS YOUR OK]**; the Terraform variables are named in
    CONTRACTS.md 12.1 with placeholder defaults 0 so nothing is invoiced
    until the owner sets them. VAT 25 % on both lines (accountant to
    confirm). The console Billing tab shows minutes per tenant per period.

11. **Swedish and English.** The provider's language detection gives the
    first language from the caller's first utterance; the agent answers in
    that language and switches when the caller does. Prompts, tool
    descriptions and fixed sentences exist in `sv` and `en`
    (`copy.py`); dates and times are spoken in Swedish convention
    ("fredag den 7 november klockan 19") with the location's timezone;
    party sizes and times are confirmed back before every write ("Ett
    bord för fyra, fredag 19.00, på namnet Sara, stämmer det?"). The agent
    never books without an explicit yes.

12. **Onboarding wizard "Så svarar vi i telefon"** (admin Telefon page,
    owner): steps (1) namn och ton: agent name (default "Booqy-assistenten"
    **[NEEDS YOUR OK: default name]**), tone `formal | friendly`, the editable
    part of the greeting with the disclosure shown as fixed text; (2)
    tider och läge: `after_hours` (default), `overflow` (forward on no
    answer), `always`; agent hours per weekday, max call length; (3)
    vidarekoppling: `transferTo` E.164, callback behaviour; (4) inspelning:
    off (default) or on with purpose and retention; (5) nummer: provision
    the Booqy number, show forwarding codes for the chosen operator, "Testa
    vidarekoppling"; (6) prova: the text simulator ("Skriv som om du
    ringde") so the owner can read the agent's answers before any call. Each
    step saves with `version`; the agent is live only after step 5.

13. **Counter-offers (owner decision 2026-11-04, DECISIONS.md).** When a
    caller asks for a table at a time, the agent follows this order and
    never invents an alternative the tools did not return:

    1. **Requested time free -> book it.** `hold_table(date, time,
       partySize)` answers `{holdId, ...}` when the party has an online
       table option at that time; the agent confirms the details back and
       books on the caller's "yes" (decision 11).
    2. **Nearby table at the requested time, when the location has a
       floor plan.** The `nearby[]` of the `hold_table` answer in step 3
       (same call). Interpretation **[NEEDS YOUR OK]**: a "nearby table"
       is a table, or two tables next to each other, at the requested
       time that the online rules would not offer this party but a staff
       member taking the call would: (a) `adjacent_pair`: two free tables
       on the same floor whose edges are at most `NEARBY_GAP_M = 1.0`
       metres apart (layout geometry is stored in metres) and whose seats
       together fit the party, and that are not already a stored
       `tableCombination` (those are online options already); (b)
       `larger`: a free table whose online rule says the party is too
       small for it (`too_large` in the availability response) but whose
       seats fit; (c) `phone_only`: a free table marked not bookable
       online (`online: false`, the "phone" reason) that fits. Without a
       published layout there are no tables at all, so `nearby` is empty
       and only steps 3-4 apply. Per location the owner can switch it off
       or narrow it: `counterOffers{nearbyTables: bool (default true),
       phoneOnlyTables: bool (default true)}` in the wizard step "tider
       och läge" and route L4 **[NEEDS YOUR OK: defaults, the 1.0 m gap]**.
       The nearby table is offered **before** the other times because it
       keeps the caller's time ("Klockan 19 finns inget vanligt bord
       ledigt, men jag kan ge er två bord bredvid varandra klockan 19.
       Vill du ha det?"); "yes" holds exactly those `tableIds` at the
       same time, "no" falls back to step 3 with the times only
       **[NEEDS YOUR OK: nearby before times]**.
    3. **Time taken -> the closest free times the same day, on both sides
       of the requested time.** The same `hold_table` call answers `{held:
       false, reason: "time_taken", time, before[], after[], nearby[]}`
       (one tool call either way, so the happy path stays inside the
       latency budget). `before` and `after` are the day's free start
       times for the party on each side of the requested time, closest
       first. The agent speaks at most **three** (`MAX_OFFERS`), chosen by
       distance from the requested time, a tie going to the earlier time,
       and spoken in clock order ("17.30, 18.30 eller 19.30")
       **[NEEDS YOUR OK: three, and earlier-wins on a tie]**. The caller
       names one, the agent holds it (step 1) and books.
    4. **Whole day full -> the next day, once.** `hold_table` answers
       `{held: false, reason: "day_full", dayFull: true}` (or
       `get_availability` answers no times); the agent asks "Vill du att
       jag kollar dagen efter?" and on "yes" calls `get_availability(date
       + 1, partySize, time)`, which ranks that day's free times by
       distance from the asked time (the time itself included when free)
       and speaks the closest three. The agent moves to the next day
       **once**: when that day is also full it offers a callback
       (`request_callback`, topic "bokning"), never a third day
       **[NEEDS YOUR OK: one day, then callback; waitlist join is v2
       (ADR-F, open question 3)]**. The day the agent moved to is the day
       being booked until the caller names another one; a day the caller
       names starts the count again, so each day the caller asks for gets
       its own next-day offer.

    **How `get_availability` offers it.** The tool wrapper in
    `phone-agent-call` (`shared/features/phone_agent/offers.py`) builds
    every answer from the existing read-only Lambdas, nothing new on their
    tables: `get-availability:live` in the guest view (`?partySize=`,
    online options per slot plus the `unavailable[{tableId, reason,
    minParty, maxParty}]` list the booking page already gets) and in the
    staff view (no `partySize`: every free table with its seats per slot),
    and for the geometry of (a) the public active layout
    `GET /locations/{l}/layout/active` served by `list-layout-version:live`
    (elements with `x`, `y`, `width`, `depth`, `floorId`, `seats`, `zone`),
    cached for the call. `get_availability` gains `time?` (the asked time;
    `timeFrom`/`timeTo` stay for ranges) and answers `{times[],
    requestedTime?, before[], after[], nearby[], dayFull}`; `hold_table`
    gains `tableIds?` (the nearby option) and answers the shapes above.
    Both compute the same `offers(...)` result; the tool list itself gains
    no tool.

    **Hold and booking path.** The public hold route (`POST
    /locations/{l}/holds`) runs Turnstile (when `TURNSTILE_REQUIRED`) and
    the per-IP request guard, neither of which the agent's synthesized
    event can satisfy, and it only accepts online options, so a nearby
    table could never be held there. Decision: the agent books the way
    staff book a phone call today, through the staff route `POST
    /locations/{l}/reservations/manual` with `source: "phone"`,
    `notifyGuest: true` and explicit `tableIds` (the agent principal is a
    staff user, decision "The agent principal"); `hold_table` is a
    bookability check with the same engine (`shared/availability`,
    read-only import) that returns a proposal id valid for the call, **not
    a server-side hold** (staff phone bookings have none today; the manual
    route's conditional write still refuses a table taken in the
    meantime, and the agent then re-offers, test row below).
    `create_reservation(holdId, ...)` books the proposal's tables.
    Consequence for decision 8: the manual route never asks a card
    guarantee, so in v1 a party that would need one online (`guarantee.required`,
    read-only import) is not booked by the agent; it gets a callback
    ("För så stora sällskap ringer restaurangen upp dig"). Upgrade
    **[NEEDS YOUR OK, Run 2 hotspot]**: the manual route accepts
    `guarantee: true` for `source: phone`, creates the reservation in the
    pending-guarantee state and returns `guaranteeRequired`, which makes
    `send_guarantee_link` work as decision 8 describes (the simulator
    scenario already drives that shape).

    **Evidence.** The call row and `PhoneCall.Ended` carry `counterOffer`
    (`none` | `other_time` | `next_day` | `nearby_table`, the last offer
    the caller accepted or, when nothing was booked, the furthest step
    reached) so the Samtal list can show "Erbjöd annan tid"; enum
    `CounterOffer` in the contract. The simulator's scripted intent table
    carries the sentences (`COUNTER_OFFERS`, `NEARBY_TABLE` in
    `shared/agent_model.py`) in Swedish and English, and
    `tests/test_phone_agent_counter_offers.py` drives every step above in
    both languages.

## Data model

Table `<prefix>phone-agent` (PAY_PER_REQUEST, PITR, deletion protection in
prod, TTL `ttl`, no stream). Tenant in every partition key.

| PK | SK | Item |
|---|---|---|
| `TENANT#<t>` | `CONFIG` | `agentName`, `tone`, `languages` (`[sv, en]`), `recording{enabled, purpose?, retentionDays?}`, `minutesCapPerMonth`, `version`, `updatedAt`, `updatedBy` |
| `TENANT#<t>` | `LOC#<l>#CONFIG` | `enabled`, `killSwitch`, `mode` (`after_hours` \| `overflow` \| `always`), `agentHours{mon..sun: [{from, to}]}`, `greetingExtraSv`, `greetingExtraEn`, `transferTo` (E.164), `maxCallSeconds`, `counterOffers{nearbyTables, phoneOnlyTables}` (decision 13, both default true), `number?{e164, providerId, provisionedAt, releaseAfter?}`, `providerAgentId?`, `forwardingVerifiedAt?`, `version` |
| `TENANT#<t>` | `NUMBER#<e164>` | pointer `{locationId}`; GSI `byNumber` |
| `TENANT#<t>` | `CALL#<yyyy-mm-dd>#<callId>` | `locationId`, `callRef` (provider), `from` (E.164, removed at contact retention), `fromHash` (`sha256(tenant\|phone)`), `status`, `startedAt`, `answeredAt?`, `endedAt?`, `durationSec`, `billedMinutes`, `metered`, `language`, `outcome` (`booked` \| `moved` \| `cancelled` \| `info` \| `transferred` \| `callback` \| `abandoned` \| `refused` \| `error`), `refusedReason?`, `disclosure{text, playedAt, repeats, languages[]}`, `counterOffer` (`none` \| `other_time` \| `next_day` \| `nearby_table`, decision 13), `reservationId?`, `callbackId?`, `transfer?{startedAt, answered, at}`, `recording?{key, expiresAt}`, `summary?` (one line by the agent, no phone number), `turnCount`, `version`, `ttl` (7 years) |
| `TENANT#<t>` | `CALL#<day>#<callId>#T#<seq:05d>` | transcript turn: `role` (`agent` \| `caller` \| `system` \| `tool`), `text`, `at`, `toolName?`, `toolArgsRedacted?`, `toolOk?`, `ttl` (24 months) |
| `TENANT#<t>` | `CALLBACK#<callbackId>` | `locationId`, `callId`, `name?`, `phone`, `phoneHash`, `topic`, `preferredTime?`, `status` (`open` \| `closed`), `createdAt`, `closedAt?`, `closedBy?`, `note?`, `version`, `ttl` (90 days after close) |
| `TENANT#<t>` | `USAGE#<periodEnd>` | `minutes`, `loc{<l>: minutes}`, `calls`, `warned80` |
| `TENANT#<t>` | `SIM#<sessionId>` | text-simulator session for the wizard: `messages[]`, `ttl` 1 hour |

GSIs: `byNumber` sparse (`GSI1PK = NUMBER#<e164>`, `GSI1SK = <t>#<l>`, on
`NUMBER#` rows; the inbound webhook resolves the called number to tenant and
location before anything else); `byReservation` sparse
(`GSI2PK = TENANT#<t>#RES#<reservationId>`, `GSI2SK = <startedAt>`, on
`CALL#` rows; the Bokningar badge). Lists by `begins_with(SK, CALL#<day>)`
and `begins_with(SK, CALLBACK#)`.

Platform row (tenant table): `PLATFORM#PHONE_AGENT/SETTINGS`
`{killSwitch, maxMinutesCap}` (console, like `PLATFORM#META_ADS`).

Bucket `<prefix>phone-agent-recordings-<account>`: `recordings/<t>/<l>/<callId>.ogg`
only with opt-in; lifecycle rules per retention tag; deleted by purge.

**The agent principal.** Existing Lambdas are invoked with a synthesized
HTTP API v2 event whose `requestContext.authorizer.jwt.claims` are
`{tenant_id: <t>, role: "staff_user", sub: "agent:<l>"}` and whose body and
path are exactly what the admin app sends. For the staff location check
(`staff_location()`) the feature keeps one system user row
`USER#agent:<l>/PROFILE` `{tenantId, role: "staff", locationId, name:
"Telefonassistent", status: "system"}` created when a location is enabled
and removed when disabled (IAM `PutItem/DeleteItem` on the user table with
`dynamodb:LeadingKeys` `StringLike "USER#agent:*"`). So the agent is held to
its location like a staff member, with no change to `shared/tenant.py`.
The reviewer checks that no listing of staff shows `status: system` rows as
people (`manage-user` list filters by status; verify in Run 2, report if
not). Alternative rejected below.

## Bedrock agent: tools and the Lambdas behind them

Every tool runs in `phone-agent-call`, scoped to the call's tenant and
location; the agent cannot name another location. Tool results are
summarised to the model (no raw rows, no other guests' names).

| Tool | Arguments | Existing Lambda and route (invoked directly on the `live` alias with the synthesized event) | Notes |
|---|---|---|---|
| `get_restaurant_info` | none | `tenant-site-config` `GET /site-config?tenantId=` | hours, special days, address, booking rules (`maxPartySizeOnline`, `bookingDurationHours`, guarantee, grace), policies; cached per call |
| `get_availability` | `date`, `partySize`, `time?`, `timeFrom?`, `timeTo?` | `get-availability` `GET /locations/{l}/availability?date=&partySize=` (guest view) and without `partySize` (staff view, every free table), plus `list-layout-version` `GET /locations/{l}/layout/active` for the floor plan (decision 13) | -> `{times[], requestedTime?, before[], after[], nearby[], dayFull}`; agent offers at most three times, closest to `time` first; full day -> the next day once, then a callback |
| `hold_table` | `date`, `time`, `partySize`, `tableIds?` | same reads as `get_availability` (`shared/availability` engine, read-only); **no write**: a bookability check returning a proposal id valid for the call | -> `{holdId, date, time, partySize, tableIds}` or `{held: false, reason: time_taken \| day_full, time, before[], after[], nearby[], dayFull?}` (decision 13); the booking itself is `create_reservation` |
| `create_reservation` | `holdId`, `name`, `phone` (caller id by default), `partySize`, `note?`, `language` | `create-pending-reservation` `POST /locations/{l}/reservations/manual` with `source: "phone"`, `notifyGuest: true`, the proposal's `tableIds` (decision 13) | confirmation SMS/email come from the existing stream; a table taken since the proposal -> the route refuses and the agent re-offers; `guaranteeRequired` only after the Run 2 hotspot upgrade of decision 13 **[NEEDS YOUR OK]**, until then guarantee-size parties get a callback |
| `send_guarantee_link` | `reservationId` | `notification:live` (kind `phone-agent.guarantee-link`), link built with `shared/manage_link.py` read-only | only when `create_reservation` said guarantee required |
| `find_reservations` | `phone?`, `fromDate?` | `get-reservation` `GET /locations/{l}/reservations?date=` for the next 14 days, filtered in the tool on `customerPhone` | never reveals a booking that does not match the caller's number unless the caller gives name and date that match |
| `move_reservation` | `reservationId`, `date`, `time`, `partySize?` | `mark-arrived` `PATCH /locations/{l}/reservations/{id}` | inside the location's change cutoff; otherwise the agent explains and offers callback |
| `cancel_reservation` | `reservationId`, `reason?` | `cancel-reservation` `POST /locations/{l}/reservations/{id}/cancel` | same cutoff rule |
| `get_menu` | `query?` | `get-menu` `GET /locations/{l}/menu` | names, categories, prices, allergen text when present; no prices for alcohol promotions |
| `transfer_to_staff` | `reason` | voice/telephony `transfer()` | section "Handoff" |
| `request_callback` | `name?`, `phone`, `topic`, `preferredTime?` | own table `CALLBACK#` | |
| `end_call` | `outcome`, `summary` | own table | the model ends; the provider's hangup also ends |

The tool list is the contract: the Run 2 builder adds nothing to it without
an ADR change. Join-the-waitlist (ADR-F) and events (ADR-K) are candidates
for v2.

## API routes

Errors `{error, code, field?}`. Staff are held to their assigned location.

| # | Method | Path | Auth | Role | Request -> response |
|---|---|---|---|---|---|
| L1 | GET | `/tenant/phone-agent` | JWT | owner | -> `{config, locations[{locationId, enabled, killSwitch, mode, number?, minutesThisPeriod}], usage{minutes, cap, includedMinutes, periodEnd}}` |
| L2 | PUT | `/tenant/phone-agent/config` | JWT | owner | `{agentName, tone, languages, recording{enabled, purpose?, retentionDays?}, minutesCapPerMonth, version}` -> config |
| L3 | GET | `/locations/{locationId}/phone-agent` | JWT | owner, staff | -> location config (staff: without `transferTo` edit, with kill switch) + `forwarding{codes[], number}` |
| L4 | PUT | `/locations/{locationId}/phone-agent` | JWT | owner | `{enabled, mode, agentHours, greetingExtraSv, greetingExtraEn, transferTo, maxCallSeconds, counterOffers{nearbyTables, phoneOnlyTables}, version}` -> config; first `enabled: true` provisions the number and the provider agent (202 `provisioning` then 200) |
| L5 | POST | `/locations/{locationId}/phone-agent/kill-switch` | JWT | owner, staff | `{on, version}` -> config |
| L6 | POST | `/locations/{locationId}/phone-agent/simulate` | JWT | owner | `{sessionId, text, language?}` -> `{reply, toolCalls[{name, ok}], state, disclosure: bool}` (text-in/text-out, same agent loop, writes nothing to bookings: tools run in `dryRun` except reads) |
| L7 | GET | `/locations/{locationId}/phone-agent/calls?from&to&cursor` | JWT | owner, staff | -> `{calls[{callId, startedAt, durationSec, language, outcome, counterOffer, reservationId?, callbackId?, summary}], cursor}` (staff: no caller number; `counterOffer` per decision 13) |
| L8 | GET | `/locations/{locationId}/phone-agent/calls/{callId}` | JWT | owner, staff | -> call (incl. `counterOffer`, decision 13) + `turns[]` + `recordingUrl?` (owner only, 5 min) |
| L9 | DELETE | `/locations/{locationId}/phone-agent/calls/{callId}/recording` | JWT | owner | -> 204 |
| L10 | GET | `/locations/{locationId}/phone-agent/callbacks?status=` | JWT | owner, staff | -> `{callbacks[]}` |
| L11 | POST | `/locations/{locationId}/phone-agent/callbacks/{callbackId}/close` | JWT | owner, staff | `{version, note?}` -> callback |
| L12 | GET | `/locations/{locationId}/phone-agent/reservations/{reservationId}/call` | JWT | owner, staff | -> `{callId, summary, disclosure, startedAt}` or 404 (Bokningar badge) |
| L13 | POST | `/public/phone-agent/telephony/webhook` | public (provider signature, throttle `public`) | none | provider body -> 200 `{}`; unknown number or bad signature 404 |
| L14 | POST | `/public/phone-agent/voice/webhook` | public (provider signature, throttle `public`) | none | provider events -> 200 |
| L15 | GET | `/platform/tenants/{tenantId}/phone-agent` | operator | platform_admin | -> `{paused, locations[{locationId, enabled, number?, minutesThisPeriod}], usage[{periodEnd, minutes}]}` |
| L16 | PUT | `/platform/tenants/{tenantId}/phone-agent` | operator | platform_admin | `{paused}` -> `{paused}` |
| L17 | GET | `/platform/phone-agent/settings` | operator | platform_admin | -> `{killSwitch, maxMinutesCap}` |
| L18 | PUT | `/platform/phone-agent/settings` | operator | platform_admin | `{killSwitch, maxMinutesCap}` -> settings |

The agent turn endpoint (`POST /v1/chat/completions`, SSE) is a Lambda
Function URL on `phone-agent-call`, not an API Gateway route (streaming);
it is listed in the module README and protected by the endpoint secret.

Errors: 400 `invalid_hours`, `invalid_phone`, `invalid_max_call`,
`invalid_cap`, `purpose_required`, `invalid_retention`, `text_too_long`;
403 `feature_not_in_plan`, `owner_only`; 404 foreign/unknown location,
call, callback, number; 409 `changed_retry`, `provisioning`,
`number_unavailable`, `invalid_state`; 502 `telephony_unavailable`,
`voice_provider_unavailable`, `ai_unavailable`.

## Events

Bus `<prefix>booqy-events`, source `booqy.phone-agent`. Common fields
`tenantId`, `occurredAt`, `version: 1`. No phone numbers, names or
transcript text in any detail.

| detail-type | extra detail |
|---|---|
| `PhoneCall.Answered` | `locationId`, `callId`, `language` |
| `PhoneCall.Ended` | `locationId`, `callId`, `durationSec`, `billedMinutes`, `outcome`, `reservationId?`, `callbackId?`, `counterOffer?` (`none` \| `other_time` \| `next_day` \| `nearby_table`, decision 13) |
| `PhoneCall.Refused` | `locationId`, `callId`, `reason: enum[cap,kill_switch,hours,paused,entitlement]` |
| `PhoneCallback.Requested` | `locationId`, `callbackId`, `callId` |
| `PhoneCallback.Closed` | `locationId`, `callbackId` |
| `PhoneMinutes.CapReached` | `periodEnd: date`, `minutes: int`, `capMinutes: int` |
| `PhoneNumber.Provisioned` | `locationId` |
| `PhoneNumber.Released` | `locationId` |

No consumer in Run 2. Guest CRM may later count `PhoneCall.Ended` with a
`reservationId` as a phone-channel visit source.

## Terraform modules

- `infrastructure/phone-agent/`: table + 2 GSIs, recordings bucket, three
  Lambdas (`phone-agent`, `phone-agent-call` with a Function URL
  `RESPONSE_STREAM` and reserved concurrency, `phone-agent-jobs` with
  Scheduler every 5 minutes for the sweep and nightly 03:00
  Europe/Stockholm for retention), roles, log groups, the `Booqy/PhoneAgent`
  alarms, secrets `${prefix}phone-agent/voice-provider`,
  `${prefix}phone-agent/telephony` (by hand, `ignore_changes`) and
  `${prefix}phone-agent/llm-endpoint-key` (`random_password`).
- Root `phone-agent.tf` passes `var.voice_client`, `var.telephony_client`,
  `var.phone_agent_model_id`, prices and the alarm threshold; routes
  `network/api-gateway/phone-agent-routes.tf`.
- IAM (new roles): table CRUD, bucket get/put/delete under its prefix,
  secrets get, `bedrock:InvokeModelWithResponseStream` on the model ARN,
  `events:PutEvents`, tenant-context read, user table Put/Delete on
  `USER#agent:*`, invoke `notification:live`, and **invoke on the six
  existing functions** `tenant-site-config:live`, `get-availability:live`,
  `create-pending-reservation:live`, `get-reservation:live`,
  `mark-arrived:live`, `cancel-reservation:live`, `get-menu:live` (seven
  with get-menu), plus `list-layout-version:live` (the public active
  layout, decision 13; eight in all). Scoping is by alias ARN, nothing on
  their tables.
- **IAM change to existing roles (call out, owner to approve):**
  `guest-privacy`, `tenant-purge` and `platform-tenants` get invoke on
  `phone-agent:live` (hooks `privacy.*`, `tenant.purge`, `platform`,
  `billing.usage`).
- `wiring` output lists the three functions, `tenant_aware_role_names` for
  all three, `staff_check_role_names` for `phone-agent` (staff routes).

## Entitlement name

`phoneAgent` (`entitlements.features.phoneAgent`; PROMPTS.md spells it
`phone_agent`, the contract keeps the camelCase convention of every other
key). Limit `phoneAgentMinutesPerMonth` (included minutes, 0-100000,
default 0). Off -> 403 on JWT routes, 404 on operator tenant routes,
webhooks answer the provider but the call is refused (`entitlement`); the
number stays reserved for 30 days (`releaseAfter`) in case the plan is
turned back on. Nothing in `/site-config`.

## Plan availability (target)

growth only; starter as a paid add-on through a per-tenant override
**[NEEDS YOUR OK: plans, included minutes, per-location price, per-minute
price]**. Run 0 addendum ships `false` and `0` in every plan.

## UI placement

- Admin, group `passet`, new item `/telefon` "Telefon" (feature
  `phoneAgent`, not ownerOnly, tour `nav-telefon`, after Personalliggare):
  tabs Samtal (list, detail with transcript, recording for owners),
  Återuppringningar, Inställningar (wizard, owner) and the kill switch
  ("Stäng av assistenten nu") visible to everyone. Page file
  `src/features/phone-agent/TelefonPage.tsx`.
- Admin `/bokningar`: slot `bokningar.panel.callbacks` (open callbacks for
  the day with "Ring upp" tel: link and "Klar") and slot
  `bokningar.reservation.call` (badge "Bokad via telefon" opening the
  transcript).
- Console: Integrations tab section `tenant.integrations.phoneAgent`
  (numbers, minutes per period, pause) and Settings card
  `settings.phoneAgent` (platform kill switch, max cap); Billing tab shows
  the two lines.
- Guest site: nothing.

Brand: a live/recording indicator (`Bar variant="live"`), a status `Chip`
for call outcomes and a transcript list style are requested from the brand
guardian (OWNERSHIP.md addendum); nothing hand-rolled.

## External dependencies

Voice provider (ElevenLabs Agents; mocked), SIP provider (46elks; mocked),
Bedrock (mocked behind `AgentModel`). **Human actions:** voice provider
account, EU residency and DPA; SIP provider account, KYC and a block of
Swedish numbers; Bedrock model access in eu-north-1 or an EU inference
profile for the chosen model; lawyer: art. 50 wording, recording notice,
privacy notice paragraph; accountant: VAT on per-location and per-minute
lines; quarterly Nova Sonic language check; verified forwarding codes per
Swedish operator.

## Privacy and GDPR

- Data: caller number, name and booking details said on the call, the
  transcript, optional audio, the agent's summary. Legal basis: art. 6(1)(b)
  (the caller asks for a booking) for the transcript and booking data;
  recording only on the restaurant's documented interest or consent
  **[NEEDS YOUR OK: lawyer decides basis and notice text]**. Booqy is
  processor; the voice and SIP providers are sub-processors (DPA list
  update, human action).
- Minimisation: the voice provider receives audio and the running
  transcript for the call only; tool results are summarised by the agent
  loop before being spoken; no tenant table data is sent as context beyond
  the location's public info. Caller number never appears in events, logs
  or error bodies (`fromHash` for lookups).
- Retention: transcript turns 24 months; `from` and `name` removed from call
  rows and callbacks by `phone-agent-jobs` after 24 months (contact rule);
  call rows 7 years (billing); recordings per the opt-in retention; open
  callbacks closed automatically after 30 days.
- Erasure and export: `privacy.export` / `privacy.erase` hooks reach calls,
  turns and callbacks by `fromHash` of the phone; erase removes `from`,
  `name`, `summary`, every turn's text (kept as `[raderad]`) and the
  recording, keeps minutes and the disclosure evidence; the reservation
  itself is erased by the existing path. `tenant.purge` deletes everything
  and releases numbers and provider agents.
- Art. 50 EU AI Act: section Decision 6; the disclosure evidence is kept as
  long as the call row.
- `shared/privacy_notice.py` gains a paragraph "Telefonassistent" when
  `phoneAgent` is on (addendum hotspot, wording **[NEEDS YOUR OK]**).
- No browser storage, no cookies.

## Swedish legal notes (human check)

- EU AI Act art. 50(1) transparency: confirm the exact Swedish and English
  wording and that "AI-assistent" is sufficient; confirm whether the
  repeat-after-interruption rule is needed or merely good practice.
- Recording: in Sweden a party to the call may record (BrB 4 kap. 9 a §),
  but GDPR requires information; confirm the notice sentence and the legal
  basis, and whether staff who receive a transferred call need a notice.
- LEK (lagen om elektronisk kommunikation) obligations for holding numbers
  on behalf of restaurants (the SIP provider is the operator; confirm Booqy
  has none).
- Pricing lines and VAT on the invoice (accountant).
- Konsumentverket: the agent gives prices from the menu including VAT;
  confirm no further duties when it reads a menu over the phone.

## Test plan

Two-tenant fixtures, `mock_aws()`, simulators for voice, telephony and the
agent model. Every JWT route: happy path, validation error, wrong role,
foreign tenant 404, entitlement off refused, idempotent retry.

| # | Validation | Wrong role | Foreign 404 | Off | Retry |
|---|---|---|---|---|---|
| L1 | n/a | staff 403 | own tenant only | 403 | n/a |
| L2 | retention 15, cap -1, purpose missing | staff 403 | n/a | 403 | stale version 409 |
| L3 | n/a | staff other location 404 | LOC_B | 403 | n/a |
| L4 | bad hours, bad E.164, max 60 | staff 403 | LOC_B | 403 | same version twice -> 409; second enable no second number |
| L5 | missing `on` | staff other location 404 | LOC_B | 403 | same state 200 |
| L6 | text > 500 chars | staff 403 | LOC_B | 403 | same sessionId + text -> same reply |
| L7 | bad range | staff other location 404 | LOC_B | 403 | n/a |
| L8 | n/a | staff gets no `from` and no recording | B's callId | 403 | n/a |
| L9 | n/a | staff 403 | B's callId | 403 | second delete 204 |
| L10 | bad status | staff other location 404 | LOC_B | 403 | n/a |
| L11 | stale version 409 | staff other location 404 | B's callbackId | 403 | second close -> same |
| L12 | n/a | staff other location 404 | B's reservationId 404 | 403 | n/a |
| L13-14 | bad signature 404, unknown number 404 | n/a | number of inactive tenant: call refused | refused `entitlement` | duplicate webhook -> one call row |
| L15-18 | bad body 400 | n/a | unknown tenant 404 | n/a | same body same result |

**Scripted call simulator** (`shared/features/phone_agent/simulator.py`,
`tests/test_phone_agent_calls.py`): text in, text out, drives the real
agent loop with `SimulatedAgentModel`, a deterministic intent table (sv and
en regexes -> tool uses) so the scenarios are reproducible without Bedrock;
a marked integration test runs the same scripts against real Bedrock when
`BEDROCK_CLIENT=real` (skipped in CI). Scenarios, each in Swedish and
English, each asserting the disclosure turn is first and
`disclosure.playedAt` is set: book inside rules; full day -> next day
offered; **counter-offers (decision 13, `tests/test_phone_agent_counter_offers.py`,
written 2026-11-04 and green on `dev`)**: requested time free -> booked
with no counter-offer; time taken -> the three closest same-day times on
both sides, clock order, tie to the earlier time; free times on one side
only; a plain "yes" to a list asks which time; an availability question
with a time ranks the day by distance; full day -> next day keeping the
asked time, the next day's own time offered when free; next day also
full -> callback, never a third day; nearby table (each of
`adjacent_pair`, `larger`, `phone_only`) offered first and held with its
`tableIds` on "yes", the times offered on "no"; no floor plan -> times
only; the ranking itself; every sentence in Swedish and English;
determinism. Run 2 adds the tool-side cases: `offers()` from the real
availability responses (both views) and a layout fixture with two tables
1.0 m apart and two 1.5 m apart; a proposal whose table is taken before
`create_reservation` -> the manual route refuses, the agent re-offers; a
guarantee-size party -> callback (until the hotspot upgrade);
`counterOffers.nearbyTables: false` -> `nearby` empty; the call row and
event carry `counterOffer`; party over the online limit -> guarantee SMS link sent, no card
data asked; move inside cutoff; cancel inside cutoff; special day closed;
menu question; unknown question -> callback row; "speak to a human" ->
transfer; transfer unanswered -> agent resumes and offers callback;
foreign-tenant isolation (tool with another tenant's reservation id ->
404 -> agent says it cannot find it); entitlement off -> refused; cap
reached mid-month -> refused with `cap`; disclosure present when
interrupted during the greeting (repeat counted); kill switch on ->
refused; max call length -> ended and processed once; two webhooks for one
end -> metered once; `simulate` route writes no reservation (dry run).
Plus: provider webhook signature tests; `USER#agent:<l>` row created and
removed; purge releases number and deletes provider agent (simulator
records calls); recording copied only with opt-in and deleted on erase;
UI at mobile, tablet, desktop, light and dark; a latency test harness that
logs `TurnLatencyMs` from the simulator with a fake 600 ms model delay and
asserts the budget below is met by the Booqy-side code (tool execution plus
overhead under 400 ms with moto).

## Latency budget

Target: caller stops speaking -> first agent audio in **1.5 s p50, 2.5 s
p95**; a turn with one booking tool call under 3.0 s p95.

| Stage | Budget | Where |
|---|---|---|
| ASR end-pointing and final transcript | 300-500 ms | voice provider |
| Provider -> our endpoint (eu-north-1 to provider EU region) | 50-100 ms | network |
| Agent loop overhead (prompt build, table reads) | < 100 ms | `phone-agent-call`, warm; reserved concurrency 2 per environment to avoid cold starts **[NEEDS YOUR OK: cost]** |
| Model first token | 400-700 ms | Bedrock, fast model |
| One tool call (`get-availability` invoke) | 150-400 ms | existing Lambda, warm |
| Second model pass after tool result, first token | 400-700 ms | Bedrock |
| TTS first byte | 150-300 ms | voice provider |

Filler sentences ("Ett ögonblick, jag kollar") are spoken by the agent
loop via `say()` when a tool call starts, so the caller never hears more
than about a second of silence. Measured in Run 3's voice QA.

## Alternatives considered

- **Speech-to-speech model as the brain (gpt-realtime, Nova Sonic)**: lower
  latency, but the booking decisions and tenant data would run outside AWS,
  against the fixed decision; Nova Sonic has no Swedish. Rejected for
  launch; Nova Sonic re-checked quarterly.
- **Step Functions per call**: durable but adds latency and cost on every
  turn; DynamoDB conditional transitions give the same idempotency.
  Rejected.
- **A new JWT role or `channel` claim in `shared/tenant.py`** for the agent
  principal: touches every handler's role handling in a hotspot; the
  system staff user row needs no shared change. Rejected for v1; revisit if
  the reviewer finds the system user visible in staff lists.
- **Calling the public guest routes through API Gateway**: needs Turnstile
  tokens and request-guard exceptions. Rejected.
- **Amazon Connect as telephony**: good AWS fit but no Swedish numbers
  without a BYOC carrier and heavier onboarding per restaurant. Rejected
  for launch.

## Open questions

1. Email concierge on the same tools (Run 3 Phase 1 if L is verified): same
   `AgentModel` and tools, different channel adapter.
2. Should staff be able to leave the agent a daily note ("fullbokat ikväll,
   vi tar inga fler")? Candidate for the Telefon page in v1.1.
3. Waitlist join by phone (ADR-F) when the day is full.
4. Outbound confirmation calls or reminders: not in scope (no outbound AI
   calls without a separate legal review).
