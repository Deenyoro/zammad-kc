# KC overlay changelog

Changes to the KawaConnect overlay (`kc/`) on top of upstream Zammad.
Upstream's own changes are in the root `CHANGELOG.md`.

## 0.0.20 (2026-11-19)

- Upstream sync to zammad develop 6a04b9626c (17 commits since ce8a9a6a08).
  Upstream changes that are visible to users: the desktop article
  translation is reworked with a choice of provider (AI, DeepL,
  LibreTranslate, each with its own settings). One new migration
  (20261116120000) adds those settings, drops the old unreleased
  translation config and switches article translation off. Chat agents
  can insert knowledge base answers, "Reply" can quote the selected text,
  ticket search by group name works for customers and agent+customer
  users, inline images without a file extension no longer fill the search
  index, Zendesk import fix. Ruby 4.0.10, viewpoint 2.0, aws-sdk-s3 1.244,
  Playwright 1.65.1.
- Patches re-anchored, no change to what they do: upstream added a field
  next to the BCC field in the article form types, so
  article-action-types-bcc.patch no longer applied exactly (CI
  verify-patches would have failed on the synced commit), and
  email-action-bcc, graphql-types-bcc and useTicketEditForm-bcc applied only
  with line offsets. All ten patches apply exactly again.

## 0.0.19 (2026-11-17)

- Upstream sync to zammad develop ce8a9a6a08 (30 commits since 225273876e).
  Upstream changes that are visible to users: the urgency a sender states in
  the email headers is kept and can be matched in postmaster filters
  (`email-urgency`), ticket search honours a state exclusion for users who
  are both agent and customer, tickets whose article preferences change
  value type can be indexed again, customer chat fixes (tags, chat number in
  the header, knowledge base answers picked with "??"), and doubled digits
  in desktop date fields. Dependency updates include redis gem 6.0.0, puma
  8.0.3, dalli 5.3.3, Formkit 2.5 and Tiptap 3.34. No database migrations.
- No overlay change was needed: all ten patches apply exactly with no line
  offsets, upstream fingerprints present, sync safety SAFE, legacy UI
  load-order check OK, type check and the KC Vitest specs pass on the
  assembled tree.

## 0.0.18 (2026-11-17)

- The "Earlier conversation" note on a new SMS ticket only quotes messages
  that went between exactly the same people. On a group text it used to
  quote any text between us and members of the group, so a three-person
  group ticket opened with two unrelated 1:1 texts and got its generated
  title from them. RingCentral and FreePBX.

## 0.0.17 (2026-11-15)

- RingCentral group texts show up as one group conversation. A group text
  used to be matched to any open or recent 1:1 ticket of one of its members
  (lookups also tried every our:member pair), so the group landed on that
  person's ticket, looked like a 1:1 chat and replies went to that person
  only. Group texts now match only their full participant set (FreePBX texts
  too), get the title "Group SMS: <members>" (contact names where known) and
  `preferences.ringcentral_sms.group`, and replies go to every participant.
  Company extension numbers RingCentral lists among a message's recipients
  (e.g. "27") are ignored; they made group replies fail.
- Microsoft Teams group chats are titled after the chat: "Teams group chat:
  <topic>", or the members' names when nobody set a topic. The old fallback
  "Group Chat #<last 8 characters of the chat id>" always read
  "Group Chat #hread.v2". Meeting chats use the meeting title. The generated
  title follows topic and member changes, also between messages (the poller
  re-reads the chat), and a title an agent typed is never replaced. A topic
  containing commas is no longer mistaken for an auto-generated one, in the
  title and in the article recipient line.
- `Kc::BackfillGroupChatTitlesJob.new.perform(dry_run:, include_closed:)`
  retitles existing group tickets (open only by default; Graph is asked for
  chat details of open tickets and of closed ones with the legacy title).
- New CI job `verify-group-chats` (`kc/spec/unit/group_chats_spec.rb`).
- Upstream sync to zammad develop 225273876e (vue-apollo 5 compat layer
  removed). KC frontend code already used the native v5 composable shape
  (0.0.13); patches apply exactly, four refreshed for line offsets only
  (TicketList, email-action-bcc, graphql-types-bcc,
  useTicketEditForm-bcc). Sync safety SAFE; upstream fingerprints present.
- New desktop UI: "Add BCC" now focuses the BCC field and opens its
  recipient dropdown like upstream's "Add CC" (it used to leave focus on CC,
  whose dropdown handed focus back while closing). The KC BCC Vitest spec
  follows upstream's CC expectations.

## 0.0.16 (2026-11-14)

- SMS ticket blocklist: group-chat entries. A line with numbers joined by `&`
  (`+14125550100 & +14125550101`) skips only conversations in which all of
  those numbers take part together; one-to-one texts with the same people
  still create tickets. Single-number lines work as before. Applies wherever
  the blocklist already applies (RingCentral and FreePBX webhooks, polling,
  backfills, outbound captures, earlier-conversation context). The setting
  text explains the format (migration `20261114000002`).

## 0.0.15 (2026-11-14)

- Microsoft 365 (Graph) mail channels with "keep messages on server" now also
  import mail that was already read. Upstream lists only unread messages, so
  an email someone opened in Outlook before Zammad's next fetch was never
  imported (ticket 188698). `Kc::MicrosoftGraphInboundReadMail` adds the read
  messages of the channel's folder received in the last
  `KC_GRAPH_READ_MAIL_WINDOW_HOURS` (default 72, max 336, `0` switches it
  off) whose Message-ID no article has yet; they are imported and marked read
  like any other message. Processed Graph message ids are remembered in
  memcached so a deleted ticket or a filtered message is not imported again.
  Boot log: `KC: MicrosoftGraphInboundReadMail, ... override is ACTIVE`.
  New CI job `verify-graph-read-mail`; upstream anchors added to
  `kc/upstream-fingerprints.txt`.

## 0.0.14 (2026-11-14)

- SMS ticket blocklist gets its own permission, `admin.kc_sms_blocklist`. The
  setting `kc_sms_ticket_blocked_numbers` now requires it instead of `admin`.
  Administrators keep access through `admin`; an API token can be given only
  this permission so automation (kc-ops) can list, add and remove blocked
  numbers without full admin rights. Migration `20261114000001` creates the
  permission and moves the existing setting; the stored numbers are unchanged.

## 0.0.13 (2026-11-14)

- Upstream sync to zammad develop 56a336d5cd (40 commits). All KC patches
  apply exactly; sync safety SAFE; 39 upstream fingerprints present.
- Upstream regenerated the desktop GraphQL composables in the vue-apollo 5
  shape (one options object instead of `variables, options`). KC conversation
  drafts still called `useUserCurrentTaskbarItemStateUpdatesSubscription`
  positionally, which the build does not type-check; the call now passes
  `{ variables, enabled }` like upstream's own callers. Before the fix the
  subscription received no taskbar item id and no enabled switch.
- 0.0.12 was released without a tag; this release is tagged.

## 0.0.12 (2026-11-06)

- Fix the legacy UI staying on "Loading..." for everyone since 2026-11-05:
  `kc_article_type_display.coffee` called `App.Event.bind` while the bundle was
  still loading, before `App.Event` exists. Its setup now waits for `App.Event`,
  `App.Utils` and `App.i18n`.
- CI guards so this cannot ship again: `verify-frontend-load-order`
  (`kc/script/check-frontend-load-order.py`) fails the build when KC CoffeeScript
  uses a `lib/app_post` class at load time; `boot-test-legacy-ui`
  (`kc/script/boot-test-bundle.js`) boots the compiled bundle from the new image
  in headless Chromium and fails on any load-time error. Deploy only digests
  whose pipeline passed it.

## 0.0.11 (2026-11-04)

- Preserve KC merged-away tickets that are displayed as closed. Incoming
  replies skip those shells and reuse the actual conversation ticket.
  Add regression coverage for closed merge shells and candidate ordering.

## 0.0.10 (2026-11-04)

- Incoming RingCentral SMS, FreePBX SMS and Teams messages reopen the same
  conversation ticket when received within 15 minutes of its latest closure.
  The message and attachments are appended through the existing article flow.
  Existing open conversations take precedence; locked and merged tickets are
  not reopened. SMS numbers, participant groups and channels, and Teams chats
  remain separate. Messages outside the window create a new ticket as before.
- Add isolated database regression tests for all three drivers and the shared
  reopen logic, required by GitLab CI before building the image.

## 0.0.9 (2026-10-29)

Zammad base: unchanged from 0.0.8 (upstream `develop` at 279d92b454).

Every KC feature was audited in both desktop UIs (legacy and the new Vue
UI) and in mobile; this release fixes what the audit found.

- **Merge into closed tickets.** Both merge dialogs now list the
  customer's closed tickets after the open ones (merged tickets and KC
  merged shells are left out, since they cannot be targets). The target
  keeps its state; a locked ticket stays locked. Discord bot 1.0.10 accepts
  closed targets in `/merge` and never opens a thread for a closed ticket.
- **New SMS / FreePBX SMS / Teams messages are draft tabs** in both
  desktop UIs, like a new ticket: a pen tab in the left sidebar that keeps
  what was typed across navigation and reloads, asks before closing a
  filled draft, and closes after sending. Several drafts can be open at
  once, and a draft started in one UI opens in the other.
- **BCC works in the new desktop UI and mobile.** The field sat among the
  ticket attributes and its value was thrown away; it is now in the reply
  form after CC (desktop: "Add BCC" next to "Add CC"), and the
  `kc_bcc_access` setting is enforced there. A plugin that crashed the
  recipient field for users without BCC access is retired.
- **BCC is hidden from customers.** The REST API returned an article's
  Bcc to the customer of the ticket.
- **Scheduled replies:**
  - Attachments are copied into the scheduled reply when it is scheduled,
    so new-UI replies keep their files (they were dropped), later uploads
    in the same tab are not sent with it, and replies scheduled more than
    30 days out no longer lose files to the upload-cache purge. Edit puts
    the files back into the editor.
  - BCC is now sent (it was dropped in both UIs).
  - New UI: the time picker no longer blocks the next hours for agents
    west of UTC; plain-text SMS/Teams replies keep their line breaks; Edit
    only reopens a reply after it was really cancelled (no double send);
    the sidebar tab shows a count of pending replies.
- **Same behaviour in both UIs:**
  - New-conversation pages start on "Default (channel group)" and list
    only groups the agent can create tickets in (a new
    `GET /api/v1/kc/conversations/groups`); the new UI pre-selects only an
    active channel. The menu says "New Teams Message" in both.
  - Bulk merge shows unless `kc_bulk_merge` is turned off, in both UIs.
  - The new UI's article action is now "Send as email reply" on internal
    notes only (the email-to-note copy is removed).
  - Legacy shows icons and readable names for Teams/SMS article types;
    mobile shows readable names (new small patch
    `ArticleMetadataDialog-kc-types.patch`).
- Type errors against the new upstream are fixed (vue-tsc is clean) and
  the two drifting patches are re-anchored.

Not in this release: the new UI's search results still have no bulk
Merge button (needs a patch to upstream's search page).

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
