# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

Rails.application.config.db_case_sensitive = true
Rails.application.config.db_like = 'ILIKE'
Rails.application.config.db_null_byte = false

# Legacy setting, not used anymore. Keep for backwards compatibility.
Rails.application.config.db_column_array = true
