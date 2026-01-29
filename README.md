# KawaConnect (KC) — Zammad Fork

A production fork of [Zammad](https://github.com/zammad/zammad) built around the **KawaConnect overlay system** — a zero-conflict extension architecture that lets you add custom backend logic, frontend UI, database schema, API routes, and gems to Zammad without ever touching an upstream file. Pull new Zammad releases with `git merge` and get zero conflicts in application code, every time.

---

## Table of Contents

- [The KawaConnect Overlay System](#the-kawaconnect-overlay-system)
  - [Why an Overlay](#why-an-overlay)
  - [Architecture](#architecture)
  - [Directory Layout](#directory-layout)
  - [Build Pipeline](#build-pipeline)
  - [Collision Detection](#collision-detection)
  - [Upstream Sync](#upstream-sync)
  - [Hardening Strategy](#hardening-strategy)
- [Extension Layers](#extension-layers)
  - [Ruby Backend (Concerns + Namespaced Classes)](#ruby-backend)
  - [API Routes](#api-routes)
  - [Legacy Frontend (CoffeeScript / ECO)](#legacy-frontend)
  - [Modern Frontend (Vue 3 / TypeScript)](#modern-frontend)
  - [Database Migrations](#database-migrations)
  - [Custom Gems](#custom-gems)
- [Included Extensions](#included-extensions)
  - [Per-Agent Time Tracking](#per-agent-time-tracking)
  - [Admin Time Management Reporting](#admin-time-management-reporting)
  - [Note / Email Reply Convert Button](#note--email-reply-convert-button)
  - [Multi-Tab Support](#multi-tab-support)
- [Getting Started](#getting-started)
- [Upstream](#upstream)

---

## The KawaConnect Overlay System

### Why an Overlay

Zammad is actively developed. Maintaining a fork with inline changes to upstream files means merge conflicts on every update, broken patches, and constant rework. The KawaConnect overlay eliminates this entirely:

- **All custom code lives in `kc/`** — a single directory at the repo root, completely separate from Zammad's source tree.
- **At Docker build time**, a shell script copies KC files into the Zammad app tree using `rsync --ignore-existing`. The flag guarantees that no upstream file is ever overwritten.
- **`git merge upstream/develop`** produces zero conflicts in `app/`, `config/`, `lib/`, and `db/` — because KC never modifies those directories in the repo. The only files with potential (trivial) conflicts are `Dockerfile` and `script/build/cleanup.sh`.
- **Removing the overlay** is as simple as deleting the `kc/` directory. The build becomes identical to upstream Zammad.

### Architecture

The overlay plugs into Zammad through six integration points, all of which are native Zammad/Rails mechanisms — no monkey-patching of the framework itself:

| Layer | Mechanism | How KC Uses It |
|-------|-----------|----------------|
| **Models** | `ActiveSupport::Concern` + `prepend` | A single initializer (`kc_loader.rb`) prepends KC concern modules into upstream models at boot time. New methods, associations, validations, and callbacks are added without editing the original class files. |
| **Controllers & Services** | `Kc::` namespace + Rails autoloading | New classes under `app/controllers/kc/` and `app/services/kc/` are picked up automatically once they land in the app tree. |
| **Routes** | Zammad's route glob (`config/routes/*.rb`) | KC drops `kc_routes.rb` into the glob directory. All routes are scoped under `/api/v1/kc/` to avoid collisions. |
| **Legacy Frontend** | `App.Config.set` plugin registry | CoffeeScript plugins register themselves into Zammad's `TicketZoomArticleAction` (and similar) config namespaces. They are auto-discovered at runtime with no manifest file. |
| **Modern Frontend** | Vite `import.meta.glob` | Zammad's desktop app globs `pages/**/routes.ts`. A `pages/kc/routes.ts` file is auto-discovered. |
| **Gems** | `Gemfile.local` | Zammad natively loads `Gemfile.local*` from the repo root (see the bottom of `Gemfile`). The overlay copies KC's `Gemfile.local` there at build time. |

### Directory Layout

```
kc/
├── Gemfile.local                                  # Custom gems (copied to repo root at build)
├── README.md                                      # Developer guide for adding extensions
├── UPGRADE.md                                     # Upgrade notes
├── UPGRADE-KUBERNETES.md                          # Kubernetes-specific upgrade notes
├── script/
│   └── apply-overlay.sh                           # Build-time overlay script
├── config/
│   ├── initializers/
│   │   ├── kc_loader.rb                           # Bootstraps Kc module, registers concern prepends
│   │   └── kc_disable_session_takeover.rb         # Disables single-session enforcement
│   └── routes/
│       └── kc_routes.rb                           # API routes under /api/v1/kc/
├── app/
│   ├── models/
│   │   ├── concerns/kc/                           # Concerns prepended into upstream models
│   │   └── kc/                                    # New standalone models
│   ├── controllers/kc/                            # New controllers
│   ├── services/kc/                               # New service objects
│   ├── policies/controllers/kc/                   # Pundit policies for KC controllers
│   ├── assets/javascripts/app/
│   │   ├── controllers/                           # CoffeeScript controllers and plugins
│   │   └── views/                                 # ECO templates
│   └── frontend/apps/desktop/pages/kc/            # Vue 3 pages (auto-discovered by Vite)
├── db/
│   └── migrate/                                   # Idempotent Rails migrations
└── lib/
    └── kc/                                        # Library code, utilities, integrations
```

### Build Pipeline

The Dockerfile adds five lines to the standard Zammad build (each is conditional and clearly marked with `# KC:` comments):

1. **`rsync`** is added to build-stage packages
2. **Overlay script** runs after `COPY . .` and before asset compilation:
   ```
   RUN if [ -x kc/script/apply-overlay.sh ]; then kc/script/apply-overlay.sh; fi
   ```
3. **Custom gems** are installed if `Gemfile.local` was copied:
   ```
   RUN if [ -f Gemfile.local ]; then bundle install ...; fi
   ```
4. **Standard Zammad build** continues (version stamp, asset precompile)
5. **Cleanup** removes the `kc/` source directory from the final image

If the `kc/` directory is empty or absent, the build behaves identically to upstream Zammad.

### Collision Detection

The overlay script (`apply-overlay.sh`) checks every KC file against the Zammad app tree before copying. If a KC file has the same path as an existing upstream file, the build aborts with a clear error listing every collision. This catches developer mistakes early — you can never accidentally shadow an upstream file.

### Upstream Sync

```bash
git remote add upstream https://github.com/zammad/zammad.git
git fetch upstream
git merge upstream/develop
```

| Path | KC Modifications | Conflict Risk |
|------|-----------------|---------------|
| `app/`, `config/`, `lib/`, `db/` | None — KC files are additive only | **Zero** |
| `Dockerfile` | 5 added lines | Low — additions are between existing blocks, marked with `# KC:` |
| `script/build/cleanup.sh` | 1 added line | Very low — appended at end |

### Hardening Strategy

Every KC file is written to degrade gracefully when upstream changes things we depend on. The app always boots — features may disable themselves, but nothing crashes:

- **Ruby initializers** use `safe_constantize` to resolve class names. If upstream renames or removes `Ticket::TimeAccounting`, the prepend is skipped with a log warning instead of crashing boot.
- **`class_eval` overrides** check both class existence (`safe_constantize`) and method existence (`method_defined?`) before patching. If the target is gone, the override is skipped.
- **CoffeeScript class extensions** save a reference to the upstream class and `extend` it (not replace it). If the upstream class is missing, a no-op stub is defined so the rest of the file loads without errors.
- **CoffeeScript plugins** wrap all DOM manipulation and event handling in `try/catch` blocks. A broken plugin logs a `console.warn` and the rest of the UI continues working.
- **The auth policy** rescues all errors and fails closed (denies access) rather than crashing the request.
- **Database migrations** check `table_exists?` and `column_exists?` before every operation. If upstream renames a table, the migration skips with a `say` message.
- **Model concerns** guard their `included` block with `rescue` and check column existence before declaring `belongs_to` associations.
- **API controllers** use `safe_constantize` for any upstream class reference that could be renamed (e.g. `Ticket::TimeAccounting::Type`) and return safe fallback values.

---

## Extension Layers

### Ruby Backend

KC extends upstream models via `ActiveSupport::Concern` modules prepended at boot time. The `kc_loader.rb` initializer is the single source of truth — one glance tells you every upstream class that KC modifies:

```ruby
kc_prepend.call('Ticket::TimeAccounting', 'Kc::TimeAccountingAgent')
```

New standalone classes use the `Kc::` namespace (`Kc::TimeManagementController`, etc.) and are autoloaded by Rails conventions.

### API Routes

All KC routes are scoped under `/api/v1/kc/` in a single file (`kc_routes.rb`). Zammad's `config/routes.rb` globs `config/routes/*.rb`, so the file is loaded automatically with no upstream modification.

### Legacy Frontend

Zammad's legacy desktop-app (CoffeeScript / Spine.js) uses a plugin registry system. KC plugins register via `App.Config.set` with a priority prefix that controls load order:

```coffeescript
App.Config.set('150-KcConvertType', KcConvertType, 'TicketZoomArticleAction')
```

Plugins implement a standard interface (`articleTypes`, `setArticleTypePost`, `action`, `perform`, etc.) and are auto-discovered by the article controller. Removing the file removes the feature — no cleanup needed.

For class extensions (replacing an upstream controller), KC saves the original class, subclasses it, and overrides only the methods that need to change. Upstream constructor logic, events, and new methods are inherited automatically via the prototype chain.

### Modern Frontend

Zammad's Vue 3 desktop app uses Vite's `import.meta.glob('../../pages/**/routes.ts')` for page discovery. KC pages go in `app/frontend/apps/desktop/pages/kc/` with a `routes.ts` file that exports Vue Router route records.

### Database Migrations

KC migrations use standard Rails migration files with idempotent guards:

```ruby
def up
  return unless table_exists?(:ticket_time_accountings)
  return if column_exists?(:ticket_time_accountings, :agent_id)
  add_reference :ticket_time_accountings, :agent, foreign_key: { to_table: :users }, null: true
end
```

Migrations are copied into `db/migrate/` by the overlay and execute during container startup via `rails db:migrate`.

### Custom Gems

`kc/Gemfile.local` is copied to the repo root at build time. Zammad's `Gemfile` natively loads `Gemfile.local*` files, so custom gems are picked up by `bundle install` during the Docker build.

---

## Included Extensions

### Per-Agent Time Tracking

The upstream time accounting sidebar groups entries by activity type. KC replaces it with a per-agent breakdown:

- A new `agent_id` column on `ticket_time_accountings` tracks which agent performed the work (distinct from `created_by_id` which is the user who logged the entry)
- The ticket sidebar groups time entries by agent, showing individual totals and line items
- Agents can add new time entries (selecting agent, activity type, and duration) and delete existing ones directly from the sidebar
- If the KC API endpoint returns 404 (e.g. overlay routes not loaded), the widget permanently falls back to the upstream render for that browser session — the sidebar never breaks

### Admin Time Management Reporting

A new admin page at **System > KC - Time Management** with two report tabs:

- **By User** — time units aggregated per agent for a selected month and year, sorted by highest total
- **By Organization** — time units aggregated per customer organization for a selected month and year

Both tabs include a month/year picker and support Excel (`.xlsx`) export via Zammad's `ExcelSheet` class.

### Note / Email Reply Convert Button

A button in the ticket compose area (legacy desktop-app) that converts between "note" and "email reply" article types:

- Preserves the typed body content across the conversion
- When converting to email: auto-populates the To field with the ticket customer's email address, inserts the email signature
- When converting to note: removes the email signature
- Mirrors the native `selectArticleType` flow exactly (`setArticleTypePre` -> `setArticleTypePost` -> event trigger -> `tokanice`)
- Only appears when both article types are available (hides automatically when the group has no email address configured)
- Removed from the DOM entirely when not applicable, preventing Zammad's `openTextarea` animation from revealing a button that should be hidden

### Multi-Tab Support

Zammad enforces single-session-per-user: opening a second browser tab broadcasts a `session_takeover` WebSocket event that disconnects all other tabs. KC disables this by redefining `Sessions::Event::SessionTakeover#run` as a no-op, allowing agents to work across multiple tabs simultaneously.

---

## Getting Started

1. Clone this repo
2. Build the Docker image (the KC overlay is applied automatically)
3. Run `rails db:migrate` on first boot to apply KC migrations
4. See `kc/README.md` for the full developer guide on adding new extensions

---

## Upstream

This fork is based on [Zammad](https://github.com/zammad/zammad), an open-source helpdesk/customer support platform licensed under the GNU AGPLv3. See [LICENSE](LICENSE) for details.
