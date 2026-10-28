# KC overlay changelog

Changes to the KawaConnect overlay (`kc/`) on top of upstream Zammad.
Upstream's own changes are in the root `CHANGELOG.md`.

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
