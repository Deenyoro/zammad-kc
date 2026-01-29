# Zammad KC Fork

A customized fork of [Zammad](https://github.com/zammad/zammad) with business-specific extensions built on top of the KC overlay system. All custom code lives in `kc/` and is applied at Docker build time via `rsync --ignore-existing` — upstream files are never modified, so pulling new Zammad releases produces zero merge conflicts in application code.

## What This Fork Adds

### Per-Agent Time Tracking

The upstream time accounting sidebar only shows totals grouped by activity type. This fork replaces it with a per-agent breakdown:

- Each time entry is assigned to a specific agent (via a new `agent_id` column on `ticket_time_accountings`)
- The ticket sidebar groups entries by agent with individual totals
- Agents can add and delete time entries inline from the sidebar
- If the KC backend is unavailable (e.g. routes not loaded), the sidebar automatically falls back to the upstream widget

**Files:** `zz_kc_time_unit.coffee`, `kc_time_unit.jst.eco`, `time_accounting_agent.rb`, migration

### Admin Time Management Reporting

A new admin page under **System > KC - Time Management** with two tabs:

- **By User** — aggregated time units per agent for a selected month/year
- **By Organization** — aggregated time units per customer organization for a selected month/year

Both views support Excel export for download.

**Files:** `kc_time_management.coffee`, `time_management_controller.rb`, ECO templates

### Note / Email Reply Convert Button

A button in the legacy desktop-app ticket compose area that lets agents convert between "note" and "email reply" article types while preserving the typed body content. When converting to email, the customer's email address is auto-populated in the To field and the email signature is inserted.

The button only appears when both article types are available (e.g. hides when the group has no email address configured).

**Files:** `kc_convert_type.coffee`

### Multi-Tab Support (Session Takeover Disabled)

Zammad's default behavior kicks you out of all other tabs when you open a new one (session takeover). This fork disables that behavior so agents can work with multiple Zammad tabs open simultaneously.

**Files:** `kc_disable_session_takeover.rb`

## How It Works

All custom code lives in the `kc/` directory. During the Docker build, `kc/script/apply-overlay.sh` copies KC files into the Zammad app tree using `rsync --ignore-existing`. Upstream files are never overwritten.

- **Ruby backend** — Concerns prepended into upstream models via `kc_loader.rb`, new controllers/services under the `Kc::` namespace
- **Routes** — Scoped under `/api/v1/kc/`, auto-loaded by Zammad's route glob
- **Legacy frontend** — CoffeeScript plugins registered via `App.Config.set`, ECO templates under KC-specific view paths
- **Migrations** — Standard Rails migrations with idempotent guards (`column_exists?`, `table_exists?`)

### Upstream Sync

```bash
git remote add upstream https://github.com/zammad/zammad.git
git fetch upstream
git merge upstream/develop
```

Zero conflicts in `app/`, `config/`, `lib/`, `db/`. The only files that can conflict are `Dockerfile` and `script/build/cleanup.sh` (minimal, clearly marked with `# KC:` comments).

### Hardening

Every KC file is hardened against upstream changes:

- Ruby initializers use `safe_constantize` and `rescue` blocks — if upstream renames or removes a class we depend on, the app boots with a warning instead of crashing
- CoffeeScript files guard against missing upstream classes and fall back gracefully
- The auth policy fails closed (denies access) on unexpected errors
- The migration checks `table_exists?` and `column_exists?` before every operation
- The overlay build script detects file collisions and aborts with a clear error

See `kc/README.md` for the full developer guide on adding new extensions.

## Upstream

This fork is based on [Zammad](https://github.com/zammad/zammad), an open-source helpdesk/customer support platform licensed under the GNU AGPLv3. See [LICENSE](LICENSE) for details.
