# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

#
# Populate the DATABASE_URL environment variable if it is not already set, for environments like docker and kubernetes.
#
database_yml_path = File.expand_path('../../config/database.yml', __dir__)

if !File.exist?(database_yml_path) && ENV['DATABASE_URL'].blank?
  if %w[POSTGRESQL_HOST POSTGRESQL_PORT POSTGRESQL_USER POSTGRESQL_DB].any? { |var| ENV[var].blank? }
    warn 'Error: The database is not configured. Please provide either config/database.yml or the correct environment variables.'
    exit 1 # rubocop:disable Rails/Exit
  end

  escaped_postgresql_pass = URI.encode_uri_component(ENV['POSTGRESQL_PASS'] || '')

  ENV['DATABASE_URL'] = "postgres://#{ENV['POSTGRESQL_USER']}:#{escaped_postgresql_pass}@#{ENV['POSTGRESQL_HOST']}:#{ENV['POSTGRESQL_PORT']}/#{ENV['POSTGRESQL_DB']}#{ENV['POSTGRESQL_OPTIONS']}"
end
