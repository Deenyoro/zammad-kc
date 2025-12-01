# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

namespace :zammad do

  namespace :bootstrap do

    desc 'Resets a Zammad instance and reinitializes it'
    task reset: %i[
      zammad:db:truncate
      db:migrate
      db:seed
      zammad:setup:auto_wizard
    ]
  end
end
