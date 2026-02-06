# KawaConnect — Zammad Fork

A production fork of [Zammad](https://github.com/zammad/zammad) with integrated communication channels and workflow enhancements for helpdesk teams.

Built on the KC overlay system — all custom code lives in `kc/` and is merged into the Zammad app tree at Docker build time using `rsync --ignore-existing`, so upstream updates merge cleanly with zero application code conflicts.

---

## Features

### Microsoft Teams Chat Integration

Bidirectional messaging between Microsoft Teams chats and Zammad tickets.

- **Inbound:** Teams chat messages create tickets automatically, with conversation threading based on a configurable time window (default 24 hours)
- **Outbound:** Agents reply from the Zammad ticket view and the message is delivered back to the Teams chat via Microsoft Graph API
- **OAuth2 setup:** Admin UI for connecting Teams accounts with client credentials and tenant configuration
- **Real-time delivery:** Graph webhook subscriptions with automatic renewal, plus backup polling every 15 minutes for reliability
- **User linking:** Teams users are matched to Zammad customers via email and linked through authorization records
- **MMS support:** Media and attachments are handled in both directions
- Admin page at **System > KC - Teams Chat** for managing connected accounts

### RingCentral SMS/MMS Integration

Send and receive SMS/MMS messages through RingCentral, with the same architecture as the Teams integration.

- **Inbound:** Incoming SMS messages create or thread into existing tickets based on phone number and time window
- **Outbound:** Agents reply via SMS directly from the ticket view, with phone number selection for multi-number accounts
- **OAuth2 setup:** Admin UI for connecting RingCentral accounts
- **Webhook + polling:** Real-time webhook delivery with subscription renewal and backup polling for missed messages
- **MMS support:** Send and receive media attachments
- **Message deduplication:** Messages are tracked by RingCentral message ID to prevent duplicates
- Admin page at **System > KC - RingCentral SMS** for managing connected accounts

### Per-Agent Time Tracking

Enhanced time accounting with agent attribution.

- A **Time Tracking** sidebar tab in the ticket view groups time entries by agent with individual totals
- Agents add entries directly from the sidebar, selecting agent, activity type, and duration
- Tracks which agent performed the work (`agent_id`) separately from who logged the entry (`created_by_id`)
- Falls back gracefully to native Zammad time tracking if the overlay is not loaded

### Admin Time Management Reporting

Reporting page at **System > KC - Time Management** with two views:

- **By User** — time units aggregated per agent for a selected month/year
- **By Organization** — time units aggregated per customer organization

Both views support month/year filtering and Excel (`.xlsx`) export.

### Note / Email Reply Conversion

A button in the ticket compose area that converts between "note" and "email reply" article types:

- Preserves the typed message body across conversion
- When converting to email: auto-populates the To field and inserts the email signature
- When converting to note: removes the email signature
- Only appears when both article types are available for the current ticket group

### New Conversation Initiators

Agent-facing pages for starting outbound conversations without an existing ticket.

- **New SMS:** Compose and send an SMS via RingCentral from the "+" new task dropdown, with recipient search by name/phone, channel selection, and optional "create ticket only" mode that sets up SMS routing without sending
- **New Teams Chat:** Start a 1:1 Teams chat from the "+" dropdown, with Azure AD directory search, automatic chat creation via Graph API, and customer user linking

### Scheduled Replies

Queue replies for future delivery with a datetime picker in the ticket compose area.

- **Schedule button** added to the ticket update dropdown alongside existing actions
- **Datetime picker modal** with future-time validation
- **Pending reply banner** in the ticket timeline shows scheduled time, preview, and cancel button
- **Background job** polls every 60 seconds with pessimistic locking (SELECT FOR UPDATE SKIP LOCKED) to prevent double-send
- Works with all article types: email, Teams Chat, RingCentral SMS, and notes
- Supports attachment transfer and ticket attribute changes at send time

### Waiting for Reply State

A custom ticket state for tracking tickets where the agent is waiting for a customer response.

- Uses the existing "open" state type so it integrates into Zammad's category system (open ticket counts, agent dropdowns, overviews)
- **Auto-transitions to "open"** when a customer creates a non-internal communication article (SMS, Teams, API)
- Postmaster (email) and web frontend already handle this natively; this concern covers the remaining paths

### Closed (Locked) States

Two custom ticket states that prevent customers from reopening tickets.

- **closed (locked)** — permanent lock using the 'closed' state type. Customer follow-ups create articles but never change the ticket state.
- **closed (locked until)** — timed lock using 'pending action' state type. The built-in pending scheduler auto-transitions to regular "closed" when pending_time expires, after which normal reopen rules apply.
- Agents and admins can always change state; system context (triggers, macros, schedulers) is allowed
- Customer articles are still created and visible to agents — only the state change is blocked

### API Health Check

Proactive monitoring of external API connections with automatic alerting.

- Checks Microsoft Graph Email, Teams Chat, and RingCentral SMS channels every 5 minutes
- Refreshes OAuth tokens and makes a lightweight API call to verify connectivity
- **Auto-creates alert tickets** on failure with actionable instructions (24-hour dedup)
- **Auto-closes alert tickets** with a recovery note when the connection is restored
- Configurable group, priority, and owner for alert tickets
- Admin page at **System > KC Extensions > API Health Check** for channel selection and settings
- Manual "Check Now" button for on-demand verification

### Multi-Tab Support

Allows agents to work across multiple browser tabs simultaneously. Zammad's default behavior disconnects previous tabs when a new one is opened — this is disabled so agents can have multiple tickets open without interruption.

---

## Overlay System

All custom code lives in the `kc/` directory. At Docker build time, `kc/script/apply-overlay.sh` copies files into the Zammad app tree without overwriting any upstream files. The build includes collision detection that aborts if a KC file would shadow an upstream file.

**Integration points:**

| Layer | Mechanism |
|-------|-----------|
| Models | `ActiveSupport::Concern` + `prepend` registered in `kc_loader.rb` |
| Controllers & Services | `Kc::` namespace, autoloaded by Rails |
| Routes | `kc_routes.rb` auto-discovered by Zammad's route glob, scoped under `/api/v1/kc/` |
| Legacy Frontend | CoffeeScript plugins registered via `App.Config.set` |
| Modern Frontend | Vite `import.meta.glob` discovers `pages/kc/routes.ts` |
| Gems | `Gemfile.local` loaded natively by Zammad's `Gemfile` |
| Migrations | Standard Rails migrations with idempotent guards |

Removing the overlay is as simple as deleting the `kc/` directory — the build becomes identical to upstream Zammad.

See `kc/README.md` for the full developer guide on adding new extensions.

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
2. Build the Docker image (the KC overlay is applied automatically)
3. Run `rails db:migrate` on first boot to apply KC migrations
4. Configure integrations via the admin panel under **System > KC**

---

## Upstream

Based on [Zammad](https://github.com/zammad/zammad), an open-source helpdesk/customer support platform licensed under the GNU AGPLv3. See [LICENSE](LICENSE) for details.
