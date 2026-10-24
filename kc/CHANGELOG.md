# KC overlay changelog

Changes to the KawaConnect overlay (`kc/`) on top of upstream Zammad.
Upstream's own changes are in the root `CHANGELOG.md`.

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
