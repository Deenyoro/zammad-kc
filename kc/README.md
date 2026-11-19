# KC Overlay System

Custom code overlay for extending Zammad without modifying upstream source files.

Incoming RingCentral SMS, FreePBX SMS and Teams customer messages reuse and
reopen the same conversation ticket for 15 minutes after its latest closure.
Existing open conversations take precedence. Locked and merged tickets stay
closed; a reply outside the window starts a new ticket. SMS channels and full
participant sets, and Teams tenant/chat identities, are matched separately.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [How the Build Works](#how-the-build-works)
- [Upstream Sync Workflow](#upstream-sync-workflow)
- [Adding Backend Code](#adding-backend-code)
  - [Adding a Concern (Extending an Upstream Model)](#adding-a-concern-extending-an-upstream-model)
  - [Adding a New Model](#adding-a-new-model)
  - [Adding a New Controller](#adding-a-new-controller)
  - [Adding a New Service](#adding-a-new-service)
  - [Adding Custom Routes](#adding-custom-routes)
  - [Adding Database Migrations](#adding-database-migrations)
  - [Adding Library Code](#adding-library-code)
  - [Adding Custom Gems](#adding-custom-gems)
- [Adding Frontend Code](#adding-frontend-code)
  - [Adding a Desktop Page](#adding-a-desktop-page)
- [Rules and Conventions](#rules-and-conventions)
- [Verification and Debugging](#verification-and-debugging)
- [Troubleshooting](#troubleshooting)

---

## Overview

All custom KC code lives inside the `kc/` directory at the repository root, completely isolated from upstream Zammad source files. During the Docker build, a shell script (`kc/script/apply-overlay.sh`) copies KC files into the Zammad application tree using `rsync --ignore-existing`, which guarantees that **no upstream file is ever overwritten**.

This means:

- Merging upstream Zammad updates (`git merge upstream/develop`) produces **zero conflicts** in application code (`app/`, `config/`, `lib/`, `db/`).
- The only files with potential merge conflicts are `Dockerfile` (5 added lines) and `script/build/cleanup.sh` (1 added line), both trivial to resolve.
- Custom code is clearly separated, easy to audit, and easy to remove.

---

## Architecture

The overlay system uses three complementary mechanisms:

| Layer | Mechanism | How It Works |
|---|---|---|
| **Ruby backend** | Rails Concerns via `prepend` | A single initializer (`kc_loader.rb`) prepends KC concern modules into upstream models at boot time. |
| **Ruby backend** | `Kc::` namespace | New models, controllers, and services live under the `Kc::` namespace. Rails autoloading picks them up automatically once they're in the app tree. |
| **Routes** | Zammad route glob | Zammad's `config/routes.rb` globs `config/routes/*.rb`, the overlay drops `kc_routes.rb` into that directory. |
| **Frontend** | Vite `import.meta.glob` | Zammad's desktop app globs `pages/**/routes.ts`, a `pages/kc/` directory with a `routes.ts` file is auto-discovered. |
| **Gems** | `Gemfile.local` | Zammad natively loads `Gemfile.local*` files from the repo root (see bottom of the main `Gemfile`). |
| **Migrations** | Standard Rails migrations | KC migrations are placed in `db/migrate/` with a `kc_` prefix in the class name for identification. |

---

## Directory Structure

```
kc/
├── README.md                                  # This file
├── Gemfile.local                              # Custom gems (copied to repo root at build time)
├── script/
│   └── apply-overlay.sh                       # Build-time overlay script
├── config/
│   ├── initializers/
│   │   └── kc_loader.rb                       # Bootstraps the Kc module, registers concerns
│   └── routes/
│       └── kc_routes.rb                       # Custom API routes under /api/v1/kc/
├── app/
│   ├── models/
│   │   ├── concerns/kc/                       # Concerns prepended into upstream models
│   │   └── kc/                                # New standalone models (Kc:: namespace)
│   ├── controllers/kc/                        # New controllers (Kc:: namespace)
│   ├── services/kc/                           # New service objects (Kc:: namespace)
│   └── frontend/apps/desktop/pages/kc/        # New frontend pages (auto-discovered by Vite)
├── db/
│   └── migrate/                               # Custom database migrations
└── lib/
    └── kc/                                    # Library code, utilities, integrations
```

At Docker build time, `apply-overlay.sh` copies the contents of `config/`, `app/`, `lib/`, and `db/` into the corresponding directories in the Zammad application tree. The `kc/` source directory is then deleted by `script/build/cleanup.sh` to keep the final image clean.

---

## How the Build Works

The Dockerfile has these additions (in order):

```
1. rsync is installed in its own RUN block (the upstream apt-get line is not touched)
2. After "COPY . .", the overlay script runs:
   RUN if [ -x kc/script/apply-overlay.sh ]; then kc/script/apply-overlay.sh; fi
3. The patches in kc/patches/ are applied to upstream files:
   RUN if [ -x kc/script/apply-patches.sh ]; then kc/script/apply-patches.sh; fi
4. If Gemfile.local was copied, custom gems are installed:
   RUN if [ -f Gemfile.local ]; then bundle install ...; fi
5. Standard Zammad build continues (VERSION stamp, asset precompile)
6. A check fails the build if asset precompilation left no manifest
7. cleanup.sh removes the kc/ source directory from the image
```

The overlay, patch and gem steps are conditional, if the `kc/` directory is absent they do nothing.

The image build does not boot the application. That is checked after the build by the `boot-test-legacy-ui` CI job (see `kc/MAINTAINING.md`, "KC Tests and CI").

### What `apply-overlay.sh` does

1. Copies `kc/Gemfile.local` to the repo root (where Zammad's `Gemfile` expects it).
2. For each of `config/`, `app/`, `lib/`, `db/`:
   - Runs `rsync --ignore-existing` to copy KC files into the Zammad app tree.
   - `--ignore-existing` is the critical flag, it **skips** any file that already exists in the target, so upstream files are never touched.
   - `.gitkeep` files are excluded from the copy.
3. Fails the build if a KC file has the same path as an upstream file (it would otherwise be skipped without notice), or if two migrations share a version number.
4. Logs every directory overlaid and the number of files copied.

### What `apply-patches.sh` does

Some features have to change an existing upstream frontend file (BCC field, bulk merge button). Those changes are unified diffs in `kc/patches/*.patch`, applied with `patch` after the overlay. A patch that does not apply fails the build. Patches in `kc/patches/retired/` are not applied. How to write and refresh a patch is in `kc/MAINTAINING.md` ("Frontend patches").

---

## Upstream Sync Workflow

```bash
# One-time setup
git remote add upstream https://github.com/zammad/zammad.git

# Sync
kc/script/check-sync-safety.sh --fetch   # exit 0 = the merge will be clean
git merge upstream/develop               # merge only, never rebase
bash kc/script/heal-patches.sh           # re-anchor drifted patches, review and commit kc/patches/
```

The full procedure, the CI jobs and the tests are in `kc/MAINTAINING.md` ("Syncing Upstream", "KC Tests and CI").

### What can conflict

| File | KC Changes | Conflict Likelihood |
|---|---|---|
| `Dockerfile` | Added lines only (rsync RUN, overlay RUN, patches RUN, gem install RUN, asset manifest check) | Low, additions are between existing blocks |
| `script/build/cleanup.sh` | Added lines only (`rm -rf kc`) | Very low, appended at end of file |
| Everything in `app/`, `config/`, `lib/`, `db/` | **None** in git. `kc/patches/` changes a few frontend files at build time only | **Zero** for the merge; a patch can stop applying (see above) |

If a conflict does occur in `Dockerfile` or `cleanup.sh`, it will be a straightforward merge because the KC additions are clearly commented with `# KC:` prefixes.

---

## Adding Backend Code

### Adding a Concern (Extending an Upstream Model)

Concerns let you add methods, callbacks, validations, and associations to upstream Zammad models without editing the original files.

**Step 1:** Create the concern module.

```ruby
# kc/app/models/concerns/kc/user_extension.rb

module Kc
  module UserExtension
    extend ActiveSupport::Concern

    included do
      # Add associations, validations, callbacks, scopes here.
      # Example:
      #   has_many :kc_widgets, class_name: 'Kc::Widget', dependent: :destroy
      #   after_create :kc_provision_defaults
    end

    # Add instance methods here.
    def kc_full_display_name
      "#{firstname} #{lastname} (#{organization&.name || 'No Org'})"
    end

    # Class methods go in a ClassMethods block.
    # class_methods do
    #   def kc_find_by_external_id(external_id)
    #     find_by(kc_external_id: external_id)
    #   end
    # end

    # private
    #
    # def kc_provision_defaults
    #   Kc::Widget.create!(user: self, name: 'Default')
    # end
  end
end
```

**Step 2:** Register the prepend in `kc/config/initializers/kc_loader.rb`.

```ruby
Rails.application.config.to_prepare do
  Rails.logger.info 'KC: Loading custom overlay extensions...'

  User.prepend Kc::UserExtension

  Rails.logger.info 'KC: Overlay loading complete.'
end
```

**How it works:** `prepend` inserts the concern module *before* the class in the method lookup chain. This means KC methods are called first and can use `super` to delegate to the original Zammad implementation. Rails' `ActiveSupport::Concern` handles `included` blocks for associations and callbacks.

### Adding a New Model

New models live under the `Kc::` namespace to avoid any name collisions with upstream.

```ruby
# kc/app/models/kc/widget.rb

class Kc::Widget < ApplicationModel
  belongs_to :user

  validates :name, presence: true

  def self.table_name
    'kc_widgets'
  end
end
```

You will also need a [migration](#adding-database-migrations) to create the table.

### Adding a New Controller

```ruby
# kc/app/controllers/kc/widgets_controller.rb

class Kc::WidgetsController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def index
    widgets = Kc::Widget.where(user: current_user)
    render json: widgets
  end

  def show
    # Scope lookups to what the caller may see. The controller policy only
    # checks the permission, not the record.
    widget = Kc::Widget.find_by!(id: params[:id], user: current_user)
    render json: widget
  end

  def create
    widget = Kc::Widget.new(widget_params)
    widget.user = current_user

    if widget.save
      render json: widget, status: :created
    else
      render json: { errors: widget.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def widget_params
    params.require(:widget).permit(:name, :description)
  end
end
```

Every controller needs a policy, `authenticate_and_authorize!` looks it up by name. Pick the narrowest permission that fits (`admin`, `ticket.agent`), and authorize the ticket or other record inside the action as well (`authorize!(ticket, :update?)`), the way the existing KC controllers do.

```ruby
# kc/app/policies/controllers/kc/widgets_controller_policy.rb

class Controllers::Kc::WidgetsControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('ticket.agent')
end
```

A public endpoint (webhook) uses `default_permit!('*')`, excludes the action from `authenticate_and_authorize!` and must authenticate the caller itself with a secret compared by `ActiveSupport::SecurityUtils.secure_compare` (see `kc/app/controllers/kc/freepbx_sms_webhook_controller.rb`).

Then add the route, see [Adding Custom Routes](#adding-custom-routes).

### Adding a New Service

```ruby
# kc/app/services/kc/sync_external_data.rb

class Kc::SyncExternalData
  def initialize(user:)
    @user = user
  end

  def execute
    # Business logic here
  end
end
```

Services are plain Ruby classes. Call them from controllers, jobs, or concerns:

```ruby
Kc::SyncExternalData.new(user: current_user).execute
```

### Adding Custom Routes

Edit `kc/config/routes/kc_routes.rb`:

```ruby
Zammad::Application.routes.draw do
  scope '/api/v1/kc', as: :kc do
    resources :widgets, controller: 'kc/widgets', only: %i[index show create update destroy]
    get  'health',  to: 'kc/health#index'
    post 'webhook', to: 'kc/webhooks#create'
  end
end
```

All custom routes are namespaced under `/api/v1/kc/` to avoid collisions with upstream Zammad API routes. This file is auto-loaded by Zammad's `config/routes.rb` which globs all files matching `config/routes/*.rb`.

### Adding Database Migrations

```ruby
# kc/db/migrate/20250129000001_create_kc_widgets.rb

class CreateKcWidgets < ActiveRecord::Migration[7.1]
  def change
    create_table :kc_widgets do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :name, null: false
      t.text       :description
      t.timestamps
    end

    add_index :kc_widgets, :name
  end
end
```

**Conventions:**
- Prefix table names with `kc_` (e.g., `kc_widgets`).
- Prefix migration class names with `Kc` or a descriptive name starting with `CreateKc`, `AddKc`, etc.
- Migrations are copied into `db/migrate/` by the overlay and run via the normal `rails db:migrate` during container startup.

### Adding Library Code

Place utility classes or modules in `kc/lib/kc/`:

```ruby
# kc/lib/kc/external_api_client.rb

module Kc
  class ExternalApiClient
    def initialize(base_url:, api_key:)
      @base_url = base_url
      @api_key  = api_key
    end

    def fetch_data(endpoint)
      # Implementation here
    end
  end
end
```

Zammad's `config.autoload_lib` in `config/application.rb` already autoloads the entire `lib/` directory, so `lib/kc/` classes resolve automatically without requiring manual `require` statements.

### Adding Custom Gems

Edit `kc/Gemfile.local`:

```ruby
gem 'httparty', '~> 0.21'
gem 'redis-objects', '~> 2.0'
```

Zammad's main `Gemfile` already includes logic to load `Gemfile.local*` files (see the bottom of `Gemfile`). The overlay script copies this file to the repo root where Zammad expects it. During the Docker build, `bundle install` runs after the overlay is applied, picking up any custom gems.

---

## Adding Frontend Code

### Adding a Desktop Page

Zammad's desktop app uses Vite's `import.meta.glob('../../pages/**/routes.ts', { eager: true })` to auto-discover page routes. Any directory under `app/frontend/apps/desktop/pages/` that contains a `routes.ts` file will be picked up automatically.

**Step 1:** Create the route definition.

```typescript
// kc/app/frontend/apps/desktop/pages/kc/routes.ts

import type { RouteRecordRaw } from 'vue-router'

const routes: RouteRecordRaw[] = [
  {
    path: '/kc',
    name: 'KcDashboard',
    component: () => import('./views/KcDashboard.vue'),
    meta: {
      title: 'KC Dashboard',
      requiresAuth: true,
      requiredPermission: ['admin'],
      icon: 'grid',
      order: 900,
      level: 1,
    },
  },
]

export default routes
```

**Step 2:** Create the Vue component.

```vue
<!-- kc/app/frontend/apps/desktop/pages/kc/views/KcDashboard.vue -->

<script setup lang="ts">
// Component logic here
</script>

<template>
  <div>
    <h1>KC Dashboard</h1>
  </div>
</template>
```

The page will appear in Zammad's navigation automatically based on the `meta` properties in the route definition. The `order` property controls the position in the nav, and `requiredPermission` controls visibility based on user roles.

---

## Rules and Conventions

1. **Never create a file in `kc/` that has the same path as an upstream Zammad file.** The overlay uses `rsync --ignore-existing`, so the KC file would never be used; `apply-overlay.sh` fails the build when it finds such a collision. To change an existing upstream file, use a concern (Ruby) or a patch in `kc/patches/` (frontend).

2. **Always use the `Kc::` namespace** for new Ruby classes (models, controllers, services, lib code). This prevents name collisions with upstream and makes KC code instantly identifiable.

3. **Prefix database tables with `kc_`** (e.g., `kc_widgets`, `kc_audit_logs`).

4. **Prefix all custom routes with `/api/v1/kc/`**: use the scope block in `kc_routes.rb`.

5. **Use concerns + `prepend` to extend upstream models.** Never copy-paste or monkey-patch upstream files. Concerns are explicit, auditable, and survive upstream updates.

6. **Register every concern prepend in `kc_loader.rb`.** This file is the single source of truth for what KC modifies in upstream Zammad. A quick glance at this file tells you exactly which models are extended.

7. **Keep the `kc/` directory self-contained.** Everything needed for KC features should be inside `kc/`. The only exceptions are the Dockerfile and cleanup.sh modifications, which are minimal and clearly marked with `# KC:` comments.

8. **Prefix KC methods with `kc_`** when adding methods to upstream models via concerns. This avoids collisions with future upstream methods. For example: `kc_full_display_name`, not `full_display_name`.

9. **Legacy UI CoffeeScript must not use `lib/app_post` classes at load time.** `app/assets/javascripts/app/index.coffee` loads `lib/app_init`, `lib/mixins`, `config`, `models`, `controllers`, `views` and only then `lib/app_post`. So `App.Event`, `App.Utils`, `App.i18n`, `App.Ajax`, `App.WebSocket` and the rest of `app_post` do not exist while a KC controller file is evaluated. Top-level statements, top-level `if`/`try` blocks and class bodies run at load time; method bodies run later. At load time, use only `App.Config.set`, models, `App.Controller` and mixins. Anything else goes in a method, or in an init that waits until the class exists (see `kc_article_type_display.coffee`). One uncaught load-time error leaves the whole UI on "Loading..." for everyone (2026-11-05/06, about 34 hours). CI enforces this rule twice: `verify-frontend-load-order` blocks the build, and `boot-test-legacy-ui` boots the compiled bundle from the built image. **Deploy only image digests whose pipeline passed `boot-test-legacy-ui`.** Run the check locally with `python3 kc/script/check-frontend-load-order.py .`.

---

## Verification and Debugging

### Build Verification

The build output shows what the overlay and patch scripts did, and both stop the build on a problem:

```
KC: Overlay applied successfully
KC: All 10 patch(es) applied successfully
```

The image build itself does not boot Zammad. The `boot-test-legacy-ui` CI job loads the compiled legacy UI from the built image, and the runtime check below confirms the Ruby side.

### Runtime Verification

Check Rails logs after container startup for:

```
KC: Loading custom overlay extensions...
KC: Overlay loading complete.
```

### Checking What Was Overlaid

During the Docker build, `apply-overlay.sh` logs every directory it processes:

```
==========================================
KC: Applying overlay
  Source: /opt/zammad/kc
  Target: /opt/zammad
==========================================
KC: Installed Gemfile.local
KC: Overlaid config/ (2 files)
KC: Overlaid app/ (5 files)
KC: Overlaid lib/ (1 files)
KC: Overlaid db/ (1 files)
==========================================
KC: Overlay applied successfully
==========================================
```

### Rails Console

To inspect KC code at runtime:

```bash
# Check if Kc module is defined
bundle exec rails runner 'puts defined?(Kc)'

# List KC models
bundle exec rails runner 'puts Kc.constants'

# Check if a concern is prepended
bundle exec rails runner 'puts User.ancestors.select { |a| a.name&.start_with?("Kc::") }'
```

---

## Troubleshooting

### Overlay script not running

- Verify the script is executable: `ls -la kc/script/apply-overlay.sh` (should show `-rwxr-xr-x`).
- Check that `rsync` is installed in the build stage (the Dockerfile has a separate KC `RUN` block for it).

### Concern not loading

- Verify the file is in `kc/app/models/concerns/kc/` and follows the correct module nesting (`module Kc; module YourConcern`).
- Verify the prepend line is in `kc/config/initializers/kc_loader.rb` inside the `to_prepare` block.
- Check Rails logs for errors during boot.

### Routes not working

- Verify `kc/config/routes/kc_routes.rb` has valid syntax.
- Run `bundle exec rails routes | grep kc` to see registered KC routes.

### Frontend page not appearing

- Verify the file is at `kc/app/frontend/apps/desktop/pages/kc/routes.ts` (the glob pattern is `pages/**/routes.ts`).
- Verify the file exports a default array of `RouteRecordRaw`.
- Check the browser console for import errors.

### Gemfile.local not picked up

- Verify the file exists at `kc/Gemfile.local`.
- Check the Docker build output for "KC: Installed Gemfile.local".
- Zammad's Gemfile globs `Gemfile.local*`, the file must be named exactly `Gemfile.local`.

### Migration not running

- Verify the migration file is in `kc/db/migrate/` with a valid timestamp prefix (e.g., `20250129000001_create_kc_widgets.rb`).
- Migrations run during container startup via `rails db:migrate`. Check container logs for migration output or errors.
