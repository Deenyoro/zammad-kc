# KawaConnect - Zammad Fork

A production fork of [Zammad](https://github.com/zammad/zammad) that extends the helpdesk platform with additional communication channels, workflow automation, and operational tooling for support teams.

KawaConnect was built to solve a core problem: reaching customers reliably across multiple channels from a single pane of glass. Out of the box, Zammad supports email and web chat - KawaConnect adds **Microsoft Teams Chat**, **RingCentral SMS/MMS**, and **outbound conversation initiation** so agents can contact customers however they prefer, all managed from the same ticket interface. Every inbound message - whether it arrives via email, Teams, or SMS - lands in the unified Zammad ticket system with full threading, history, and assignment.

Because Zammad does not offer a native mobile app, KawaConnect pairs with the [Zammad KC Discord Bot](https://github.com/Deenyoro/Zammad-KC-Discord-Bot/) to give agents full ticket management from their phone. Every open ticket gets a Discord thread with real-time bidirectional sync - agents can reply to customers, add internal notes, change ticket state/owner/priority, log time, and receive instant alerts, all from the Discord mobile app. The `/reply` command automatically detects whether the ticket uses email, SMS, or Teams and routes the response through the correct channel.

All custom code lives in the `kc/` directory and is merged into the Zammad app tree at Docker build time using `rsync --ignore-existing`, so upstream Zammad updates merge cleanly with zero application code conflicts. See the [Overlay System](#overlay-system) section for details.

---

## Table of Contents

- [Features](#features)
  - [Microsoft Teams Chat Integration](#microsoft-teams-chat-integration)
  - [RingCentral SMS/MMS Integration](#ringcentral-smsmms-integration)
  - [New Conversation Initiators](#new-conversation-initiators)
  - [Discord Bot Integration](#discord-bot-integration)
  - [Scheduled Replies](#scheduled-replies)
  - [Notification Suppression](#notification-suppression)
  - [Waiting for Reply State](#waiting-for-reply-state)
  - [Closed (Locked) States](#closed-locked-states)
  - [Per-Agent Time Tracking](#per-agent-time-tracking)
  - [Admin Time Management Reporting](#admin-time-management-reporting)
  - [Note / Email Reply Conversion](#note--email-reply-conversion)
  - [API Health Check](#api-health-check)
  - [Multi-Tab Support](#multi-tab-support)
  - [Upstream Bug Fixes](#upstream-bug-fixes)
- [Overlay System](#overlay-system)
- [Build Process](#build-process)
- [Upstream Sync](#upstream-sync)
- [Getting Started](#getting-started)
- [Admin UI Reference](#admin-ui-reference)
- [Architecture Reference](#architecture-reference)

---

## Features

### Microsoft Teams Chat Integration

Bidirectional messaging between Microsoft Teams 1:1 chats and Zammad tickets.

- **Inbound:** Teams chat messages create tickets automatically, with conversation threading based on a configurable time window (default 24 hours). Messages from the same Teams user within the window are grouped into a single ticket.
- **Outbound:** Agents reply from the Zammad ticket view and the message is delivered back to the Teams chat via Microsoft Graph API. A dedicated "Teams Chat Reply" article action appears on tickets with an active Teams conversation.
- **OAuth2 setup:** Full admin UI for connecting Azure AD applications with client credentials, tenant configuration, and redirect URI management.
- **Real-time delivery:** Graph webhook subscriptions with automatic renewal (background job), plus backup polling every 15 minutes for reliability in case webhooks are delayed or missed.
- **Directory sync:** Syncs Azure AD users into Zammad as customers, with optional phone number and job title mapping. Can optionally deactivate Zammad users no longer found in Azure AD.
- **User linking:** Teams users are matched to Zammad customers via email and linked through authorization records for identity continuity.
- **Outbound capture:** Messages sent by agents directly from the Teams app (not through Zammad) are captured by the poll job and logged as internal notes labeled "Sent via Teams" for full conversation context.
- **Attachment support:** Media and file attachments are handled in both directions.
- Admin page at **System > KC Extensions > Teams Chat**

### RingCentral SMS/MMS Integration

Send and receive SMS/MMS messages through RingCentral, with the same dual-delivery architecture as the Teams integration.

- **Inbound:** Incoming SMS messages create or thread into existing tickets based on phone number pairs and a configurable time window.
- **Outbound:** Agents reply via SMS directly from the ticket view. Multi-number accounts support phone number selection per channel.
- **OAuth2 setup:** Admin UI for connecting RingCentral accounts with a guided setup flow including phone number selection.
- **Webhook + polling:** Real-time webhook delivery with subscription renewal and backup polling for missed messages. Webhook validation prevents spoofed messages.
- **MMS support:** Send and receive media attachments. Outbound MMS sends text first, then attachments separately per RingCentral API requirements.
- **Missed call tracking:** Configurable detection of missed calls with automatic ticket creation and optional auto-reply SMS ("Sorry we missed your call...").
- **Message deduplication:** All messages are tracked by RingCentral message ID to prevent duplicates across webhook and poll delivery paths.
- **Outbound capture:** SMS messages sent from the RingCentral app directly are captured by the poll job and logged as internal notes for context.
- **Skip-send mode:** Agents can create SMS-routed tickets without sending an initial message, useful for logging phone calls or walk-in interactions that should be tracked via SMS going forward.
- Admin page at **System > KC Extensions > RingCentral SMS**

### New Conversation Initiators

Agent-facing pages for starting outbound conversations without an existing ticket. Accessible from the "+" new task dropdown in the main navigation.

- **New SMS Conversation:** Compose and send an SMS via RingCentral with recipient search by name or phone number, channel selection for multi-number accounts, and an optional "create ticket only" mode that sets up SMS routing without sending a message.
- **New Teams Chat Conversation:** Start a 1:1 Teams chat with Azure AD directory search, automatic chat creation via Graph API, and customer user linking. The first message creates both the Teams chat and the Zammad ticket simultaneously.

### Discord Bot Integration

Full ticket management from Discord, designed as a mobile-friendly alternative to the Zammad web UI. See the [Zammad KC Discord Bot](https://github.com/Deenyoro/Zammad-KC-Discord-Bot/) repository for setup.

- **Ticket threads:** Every open Zammad ticket gets a Discord thread with a color-coded embed. Threads auto-lock when tickets close and unlock when reopened. Thread titles update when ticket titles change.
- **Bidirectional sync:** Discord thread messages sync to Zammad as internal notes. Zammad articles appear in Discord threads in chronological order with full attachment support.
- **Smart routing:** The `/reply` command detects whether the ticket uses email, SMS, or Teams and routes the agent's response through the correct channel automatically.
- **Ticket commands:** `/reply`, `/note`, `/owner`, `/ticket info`, `/ticket close`, `/ticket state`, `/ticket assign`, `/ticket priority`, `/ticket time` - all work directly from phone or desktop.
- **Agent auto-join:** Users with a configured Discord role are automatically added to every open ticket thread.
- **Health monitoring:** Bot status turns red if Zammad becomes unreachable, with `@everyone` alerts in the ticket channel during outages and automatic recovery notification.
- **Deployment:** Docker Compose or Kubernetes with persistent SQLite storage.

### Scheduled Replies

Queue replies for future delivery with a datetime picker in the ticket compose area.

- **Schedule button** added to the ticket update dropdown alongside existing actions (Submit, Submit as Macro, etc.)
- **Datetime picker modal** with future-time validation - prevents scheduling in the past
- **Pending reply banner** in the ticket timeline shows the scheduled time, article preview, and a cancel button
- **Background job** polls every 60 seconds with pessimistic locking (`SELECT FOR UPDATE SKIP LOCKED`) to prevent double-send in multi-worker deployments
- Works with all article types: email, Teams Chat, RingCentral SMS, and notes
- Supports attachment transfer and ticket attribute changes (state, priority, owner) applied at send time
- Cancelled scheduled replies clean up cached attachments automatically

### Notification Suppression

Configurable suppression of agent notifications for note-type articles. Useful for reducing noise from internal notes, particularly automated internal notes generated by Teams Chat and SMS integrations.

- **Suppress internal note notifications** - when enabled, agents do not receive email or online notifications for internal notes. Public articles are unaffected.
- **Suppress all note notifications** - when enabled, agents do not receive notifications for any note-type article, whether internal or public.
- Both settings default to off (opt-in) and are independently toggleable.
- Admin page at **System > KC Extensions > Notification Settings**

### Waiting for Reply State

A custom ticket state for tracking tickets where the agent is waiting for a customer response.

- Uses the existing "open" state type so it integrates naturally into Zammad's category system - open ticket counts, agent dropdowns, overviews, and SLA calculations all treat it as an open ticket.
- **Auto-transitions to "open"** when a customer creates a non-internal communication article via SMS, Teams, or API. The agent set "waiting for reply" intentionally, so only customer activity resets it.
- Postmaster (email) and Zammad's web frontend already handle state transitions natively for their channels; this concern covers the remaining article creation paths (REST API, GraphQL, and KC integrations).

### Closed (Locked) States

Two custom ticket states that prevent customers from reopening tickets.

- **closed (locked)** - permanent lock using the "closed" state type. Customer follow-ups (email, SMS, Teams) create articles visible to agents but the ticket state is never changed. The ticket stays closed.
- **closed (locked until)** - timed lock using the "pending action" state type with a configurable `pending_time`. Zammad's built-in pending scheduler auto-transitions to regular "closed" when the time expires, after which normal reopen rules apply.
- **Agent override:** Agents and admins can always change the state of locked tickets. Only customer-initiated state changes are blocked.
- **System context allowed:** Triggers, macros, and schedulers operate normally - only interactive customer activity is restricted.
- Customer articles are always created and visible to agents - only the state change is blocked, never the message itself.

### Per-Agent Time Tracking

Enhanced time accounting with explicit agent attribution.

- A **Time Tracking** sidebar tab in the ticket view (clock icon) groups time entries by agent with individual totals and a running total for the ticket.
- Agents add entries directly from the sidebar, selecting the performing agent, activity type, and duration.
- Tracks which agent performed the work (`agent_id`) separately from who logged the entry (`created_by_id`), supporting scenarios where a supervisor logs time on behalf of a team member.
- Falls back gracefully to native Zammad time tracking if the KC overlay is not loaded - the `agent_id` column is optional and guarded.

### Admin Time Management Reporting

Reporting page at **System > KC Extensions > Time Management** with two views:

- **By User** - time units aggregated per agent for a selected month/year, with individual ticket breakdowns
- **By Organization** - time units aggregated per customer organization for a selected month/year

Both views support month/year filtering and Excel (`.xlsx`) export for billing and payroll workflows.

### Note / Email Reply Conversion

A button in the ticket compose area that converts between "note" and "email reply" article types while preserving the message body.

- Preserves the typed message body across conversion - no content is lost
- When converting note to email: auto-populates the To field with the ticket customer's email address and inserts the group's email signature
- When converting email to note: removes the email signature and clears the recipient fields
- Only appears when both article types are available for the current ticket group (requires an email address configured on the group)
- Positioned alongside the existing article type and visibility controls in the compose toolbar

### API Health Check

Proactive monitoring of external API connections with automatic alerting.

- Checks Microsoft Graph (Email and Teams Chat) and RingCentral SMS channels every 5 minutes via a background scheduler
- Refreshes OAuth tokens proactively and makes a lightweight API call to verify connectivity
- **Auto-creates alert tickets** on failure with channel-specific diagnostic details and actionable instructions (24-hour dedup prevents alert spam)
- **Auto-closes alert tickets** with a recovery note when the connection is restored
- Configurable target group, priority, and owner for alert tickets
- Channel selection - choose which channels to monitor
- Manual "Check Now" button for on-demand verification
- Admin page at **System > KC Extensions > API Health Check**

### Multi-Tab Support

Allows agents to work across multiple browser tabs simultaneously. Zammad's default behavior disconnects previous tabs when a new one is opened - KawaConnect disables this enforcement so agents can have multiple tickets open in separate tabs without interruption.

### Upstream Bug Fixes

KawaConnect includes targeted fixes for upstream Zammad bugs that affect KC integrations:

- **Origin-by-sender comparison fix** - Zammad's `AddsMetadataGeneral` compares a User object to an Integer ID (`origin_by == created_by_id`), which always evaluates to false. This breaks outbound delivery for Teams and SMS because the communicate jobs check for `sender="Agent"` before sending. The KC fix applies the corrected Integer-to-Integer comparison for Teams and SMS article types only, leaving all other article types on the original upstream behavior. If upstream fixes this bug in a future release, the KC fix produces identical results and can be safely removed.

---

## Overlay System

All custom code lives in the `kc/` directory. At Docker build time, `kc/script/apply-overlay.sh` copies files into the Zammad app tree without overwriting any upstream files. The build includes two safety checks that abort on failure:

1. **File collision detection** - if a KC file would shadow an existing upstream file, the build fails with a list of conflicting paths.
2. **Migration version detection** - if any two migration files (KC or upstream) share a version number, the build fails with a list of conflicting versions.

**Integration points:**

| Layer | Mechanism |
|-------|-----------|
| Models | `ActiveSupport::Concern` + `prepend` registered in `kc_loader.rb` |
| Controllers & Services | `Kc::` namespace, autoloaded by Rails |
| Routes | `kc_routes.rb` auto-discovered by Zammad's route glob, scoped under `/api/v1/kc/` |
| Legacy Frontend | CoffeeScript controllers and plugins registered via `App.Config.set` |
| Modern Frontend | Vite `import.meta.glob` discovers `pages/kc/routes.ts` |
| Gems | `Gemfile.local` loaded natively by Zammad's `Gemfile` |
| Migrations | Standard Rails migrations with idempotent guards (`create_if_not_exists`, `table_exists?`) |
| Background Jobs | `ApplicationJob` subclasses processed by Delayed Job with retry and error handling |

**Concern prepends (what KC modifies in upstream Zammad):**

| Upstream Class | KC Concern | Purpose |
|----------------|------------|---------|
| `Ticket::TimeAccounting` | `Kc::TimeAccountingAgent` | Adds `agent_id` association for per-agent time tracking |
| `Ticket::Article` | `Kc::EnqueueCommunicateTeamsChatJob` | Triggers outbound Teams delivery after article creation |
| `Ticket::Article` | `Kc::EnqueueCommunicateRingcentralSmsJob` | Triggers outbound SMS delivery after article creation |
| `Ticket::Article` | `Kc::FixOriginBySenderOverride` | Fixes upstream sender comparison bug for Teams/SMS articles |
| `Ticket::Article` | `Kc::ResetsWaitingForReplyState` | Auto-transitions "waiting for reply" to "open" on customer reply |
| `Ticket` | `Kc::PreventsLockedTicketReopen` | Blocks customer state changes on locked tickets |
| `Transaction::Notification` | `Kc::SuppressInternalNoteNotifications` | Optionally suppresses notifications for note articles |

Removing the overlay is as simple as deleting the `kc/` directory - the build becomes identical to upstream Zammad.

See [`kc/README.md`](kc/README.md) for the full developer guide on adding new extensions.

---

## Build Process

The Dockerfile has these additions (in order):

1. `rsync` is added to build-stage packages
2. After `COPY . .` - the overlay script runs: `kc/script/apply-overlay.sh`
3. If `Gemfile.local` was copied, custom gems are installed via `bundle install`
4. Standard Zammad build continues (VERSION stamp, asset precompile)
5. Smoke test verifies the app boots with the overlay
6. `cleanup.sh` removes the `kc/` source directory from the final image

Every step is conditional - if the `kc/` directory is empty or absent, the build behaves identically to upstream Zammad.

---

## Upstream Sync

```bash
git remote add upstream https://github.com/zammad/zammad.git
git fetch upstream
git merge upstream/develop
```

All code under `app/`, `config/`, `lib/`, and `db/` merges with zero conflicts. The only files with potential (trivial) conflicts are `Dockerfile` and `script/build/cleanup.sh`, both clearly marked with `# KC:` comments.

---

## Getting Started

1. Clone this repo
2. Build the Docker image (the KC overlay is applied automatically during the build)
3. Run `rails db:migrate` on first boot to apply KC migrations
4. Configure integrations via the admin panel under **System > KC Extensions**
5. (Optional) Set up the [Discord Bot](https://github.com/Deenyoro/Zammad-KC-Discord-Bot/) for mobile ticket management

---

## Admin UI Reference

All KC settings are managed under **System > KC Extensions** in the Zammad admin panel:

| Page | Location | Purpose |
|------|----------|---------|
| Teams Chat | KC Extensions > Teams Chat | Connect/manage Teams accounts, OAuth, directory sync settings |
| RingCentral SMS | KC Extensions > RingCentral SMS | Connect/manage RingCentral accounts, OAuth, missed call settings |
| API Health Check | KC Extensions > API Health Check | Select monitored channels, configure alert ticket settings |
| Notification Settings | KC Extensions > Notification Settings | Toggle notification suppression for internal and/or all notes |
| Time Management | KC Extensions > Time Management | Time reporting by user and by organization with Excel export |

---

## Architecture Reference

### Channel Drivers

| Driver | File | Protocol |
|--------|------|----------|
| `Channel::Driver::KcMicrosoftTeamsChat` | `app/models/channel/driver/` | Microsoft Graph API (OAuth2 client credentials) |
| `Channel::Driver::KcRingcentralSms` | `app/models/channel/driver/` | RingCentral REST API (OAuth2 authorization code) |

### API Libraries

| Library | File | Purpose |
|---------|------|---------|
| `Kc::MicrosoftTeamsGraph` | `lib/kc/microsoft_teams_graph.rb` | Graph API client for chats, messages, subscriptions, directory |
| `Kc::RingcentralApi` | `lib/kc/ringcentral_api.rb` | RingCentral API client for SMS, subscriptions, call log |

### Background Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `Kc::CommunicateTeamsChatJob` | On article create | Delivers outbound Teams messages |
| `Kc::CommunicateRingcentralSmsJob` | On article create | Delivers outbound SMS messages |
| `Kc::PollTeamsChatMessagesJob` | Every 15 min | Backup poll for Teams messages |
| `Kc::PollRingcentralSmsMessagesJob` | Every 15 min | Backup poll for SMS messages |
| `Kc::PollRingcentralMissedCallsJob` | Every 5 min | Missed call detection and auto-reply |
| `Kc::RenewTeamsSubscriptionsJob` | Every 30 min | Renews Graph webhook subscriptions |
| `Kc::RenewRingcentralSubscriptionsJob` | Every 30 min | Renews RingCentral webhook subscriptions |
| `Kc::TeamsDirectorySyncJob` | Configurable | Syncs Azure AD users to Zammad |
| `Kc::ProcessTeamsChatWebhookJob` | On webhook | Processes inbound Teams webhook payloads |
| `Kc::ProcessRingcentralSmsWebhookJob` | On webhook | Processes inbound RingCentral webhook payloads |
| `Kc::ApiHealthCheckJob` | Every 5 min | Checks API connectivity, creates/closes alert tickets |
| `Kc::SendScheduledArticlesJob` | Every 60 sec | Sends due scheduled articles with pessimistic locking |

### API Routes

All KC routes are scoped under `/api/v1/kc/`:

| Endpoint | Controller | Auth |
|----------|-----------|------|
| `GET/POST/DELETE /tickets/:id/time_entries` | `Kc::TimeManagementController` | Agent |
| `GET /time_management/by_user/:year/:month` | `Kc::TimeManagementController` | Admin |
| `GET /time_management/by_organization/:year/:month` | `Kc::TimeManagementController` | Admin |
| `GET/POST/PUT/DELETE /teams_chat_channels/*` | `Kc::TeamsChatChannelsController` | Admin |
| `POST /teams_chat_webhook` | `Kc::TeamsChatWebhookController` | Public (validated) |
| `GET/POST/PUT/DELETE /ringcentral_sms_channels/*` | `Kc::RingcentralSmsChannelsController` | Admin |
| `POST /ringcentral_sms_webhook` | `Kc::RingcentralSmsWebhookController` | Public (validated) |
| `GET/POST/DELETE /tickets/:id/scheduled_articles` | `Kc::ScheduledArticlesController` | Agent |
| `GET/PUT /api_health_check` | `Kc::ApiHealthCheckController` | Admin |
| `POST /api_health_check/check_now` | `Kc::ApiHealthCheckController` | Admin |
| `POST /conversations/sms` | `Kc::NewConversationsController` | Agent |
| `POST /conversations/teams` | `Kc::NewConversationsController` | Agent |
| `GET /conversations/sms_users` | `Kc::NewConversationsController` | Agent |
| `GET /conversations/teams_contacts` | `Kc::NewConversationsController` | Agent |

---

## Upstream

Based on [Zammad](https://github.com/zammad/zammad), an open-source helpdesk/customer support platform licensed under the GNU AGPLv3. See [LICENSE](LICENSE) for details.
