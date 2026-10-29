# KC overlay changelog

Changes to the KawaConnect overlay (`kc/`) on top of upstream Zammad.
Upstream's own changes are in the root `CHANGELOG.md`.

## 0.0.8 (2026-10-29)

Zammad base: upstream `develop` at 279d92b454 (synced 2026-10-29, 58
upstream commits since 0.0.7, including Ruby 3.4.12). All 8 frontend
patches apply, the sync-safety check is clean, and the KC suite plus
upstream's article specs pass on the new base (323 examples).

- Every Teams, SMS and missed-call article now records who it went to in
  its "To" field. Before, inbound texts and Teams messages had no
  recipient, and an agent's reply kept whatever the reply form held (one
  number of a group text, or nothing for Teams) while the delivery jobs
  sent to every participant.
  - SMS (RingCentral and FreePBX): contact name and number of every
    recipient, resolved the same way the delivery jobs pick them, e.g.
    "Jane Smith (+14125550100), +14125550111".
  - Teams: the other person in a one-on-one chat, our Teams account for
    incoming messages, and 'Group chat "Topic" (Ann Lee, Bob Ray)' for
    group chats. The Teams driver now keeps the chat type, topic and
    member names on the ticket (`preferences.teams_chat.audience`); older
    tickets fall back to the customer's name until the next message.
  - Missed calls: the number that was dialed.
  - Email is unchanged.
  The Discord bot (1.0.9) shows this line at the top of each message.
  Existing articles are not rewritten.

## 0.0.7 (2026-10-28)

Zammad base: unchanged from 0.0.1 (upstream `develop` at 0f1f86bbc2).

- Tests only, no change for users. Four KC specs failed because of how
  they set up their data, not because of a bug: two created channels
  without the required "updated by" user, and the scheduled-reply spec
  called the sending service outside the user context the scheduler job
  provides. They are fixed, and a new example sends a due scheduled reply
  through the scheduler job and checks it is created as the agent who
  scheduled it. The whole KC suite passes (75 examples).
- Four older KC migrations (FreePBX integration, escalation calls,
  escalation call state, FreePBX call history) now skip a database that is
  not set up yet, like the other KC migrations, so preparing a fresh test
  database no longer fails. Databases that already ran them are not
  affected.

## 0.0.6 (2026-10-28)

Zammad base: unchanged from 0.0.1 (upstream `develop` at 0f1f86bbc2).

- RingCentral contact sync, in both directions, per RingCentral SMS account.
  Both directions are off until turned on in Admin > KC Extensions >
  RingCentral SMS > Edit ("Import RingCentral contacts into Zammad",
  "Export directory numbers to RingCentral").
  - Import: contacts in the account's RingCentral address book become
    customers in Zammad, or are matched to an existing user by email, then
    by phone number. Customers that were named after their own number get
    the contact's name. Anyone else only has empty fields filled in: names
    and emails already set are never changed. A contact's company is linked
    when an organization with exactly that name exists; organizations are
    never created.
  - Export: every active Microsoft 365 directory user (all tenants) with a
    phone or mobile number gets a contact in the RingCentral address book
    with their name, organization, email and numbers, kept up to date. If
    staff already have a contact for that number it is left exactly as it
    is. Synced contacts carry "Synced from Zammad directory" in their notes;
    removing that line, or deleting the contact, makes Zammad leave it alone.
    Nothing is ever deleted in RingCentral, including the contacts of people
    who are later deactivated in the directory.
  - Contacts exported from Zammad are never imported back.
  - Runs every 6 hours and from a new "Sync contacts now" button. The
    admin page shows the last run: created, updated, unchanged, skipped,
    errors and the last problem (for example a missing RingCentral
    permission). Changes to RingCentral are paced to stay inside its rate
    limit; if RingCentral still says to slow down, the rest is done on the
    next run.
- New specs: `kc/spec/services/kc/ringcentral_contact_sync_spec.rb`,
  `kc/spec/lib/kc/ringcentral_api_spec.rb`,
  `kc/spec/jobs/kc/ringcentral_contact_sync_job_spec.rb`,
  `kc/spec/requests/kc/ringcentral_contact_sync_spec.rb`.

## 0.0.5 (2026-10-28)

Zammad base: unchanged from 0.0.1 (upstream `develop` at 0f1f86bbc2).

- New conversations (SMS, Teams, FreePBX texting): the agent now needs
  create access to the destination group, the same rule Zammad applies to
  normal ticket creation. Before, any agent could open a ticket in any group
  by passing its id. A refused group answers 403 before anything is sent or
  created; this also applies when the channel's default group is used.
- Scheduled replies: at send time the reply is only sent if the agent who
  scheduled it is still active and can still change the ticket. Otherwise it
  is marked failed with the reason, like other scheduled-reply failures.
- New specs: `kc/spec/requests/kc/new_conversations_spec.rb`,
  `kc/spec/services/kc/execute_scheduled_article_spec.rb`.

## 0.0.4 (2026-10-28)

Zammad base: unchanged from 0.0.1 (upstream `develop` at 0f1f86bbc2).

- Teams chat (security): a file attachment whose link points somewhere other
  than Microsoft Graph is no longer downloaded. Before, Zammad fetched any
  link a message carried and sent the connected account's Microsoft access
  token along with it, so a crafted message could collect the token or make
  the server request internal addresses. Such files now appear as a link at
  the end of the article.
- Teams chat: a message picked up by the webhook and the 30-second poll at
  the same moment was filed twice, and a chat's first message could open two
  tickets. Each chat is now processed one message at a time and the
  duplicate check is repeated under that lock.
- FreePBX texting: media links pointing at another host no longer receive
  the connection token; only the connector itself does.
- New spec: `kc/spec/models/channel/driver/kc_microsoft_teams_chat_spec.rb`.

## 0.0.3 (2026-10-24)

Zammad base: unchanged from 0.0.1 (upstream `develop` at 0f1f86bbc2).

- Teams chat: the "Detected connected account message" and "Detected agent
  message" lines are now debug level. The poll re-reads every recent message
  each 30-second cycle (the driver's dedup check runs later), so at info level
  they repeated for already-imported messages, about 80 lines a minute.

## 0.0.2 (2026-10-24)

Zammad base: unchanged from 0.0.1 (upstream `develop` at 0f1f86bbc2).

- Teams chat: each Teams channel now polls and subscribes only to chats from
  its own Microsoft 365 tenant (the ticket's `teams_chat.tenant_id`). Before,
  every channel polled every open Teams ticket's chat, so the other tenants'
  accounts hit Graph 403 ("Failed for active chat", "Graph refused
  subscription") on every 30-second cycle. Tickets without a recorded tenant
  keep the old behaviour.
- New spec: `kc/spec/jobs/kc/poll_teams_chat_messages_job_spec.rb`.

## 0.0.1 (2026-10-23)

Zammad base: upstream `develop` at 0f1f86bbc2 (7.3.x, 2026-10-23).

- First versioned KC release. Images are now also tagged by KC version
  (`ghcr.io/deenyoro/zammad-kc:0.0.1`), next to the `develop-<sha>` builds.
- Synced with the latest upstream Zammad develop branch.
- Fixed: the "Send with text color" option in the desktop ticket Update
  menu. Upstream reworked the Update button, so the KC patch no longer
  applied and the image build failed. The patch was rebuilt on the new
  upstream code.
- Fixed: emails sent through the API "on behalf of" another agent again show
  that agent's name in the From line. Upstream moved the code that builds the
  sender name in August, which had quietly switched the KC fix off; it now
  hooks the new upstream method.
- Retired the KC fix for quoted inline images failing with an "invalid
  base64" error. Upstream fixed the same bug (#5955), so the KC patch is no
  longer applied (kept in `kc/patches/retired/`).
