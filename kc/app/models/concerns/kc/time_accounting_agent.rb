# KC: Extend Ticket::TimeAccounting with an explicit agent assignment.
# When agent_id is set, it represents the person who did the work.
# When nil, falls back to created_by_id (backward-compatible).
#
# Safety:
#   - The belongs_to is only registered if the agent_id column exists,
#     so this concern is safe to load even before the migration has run.
#   - effective_agent rescues all errors so callers never crash.
#   - The included block rescues StandardError so a schema mismatch
#     (e.g. upstream dropped the table temporarily during migration)
#     logs a warning instead of crashing boot.
module Kc
  module TimeAccountingAgent
    extend ActiveSupport::Concern

    prepended do
      if table_exists? && column_names.include?('agent_id')
        belongs_to :agent, class_name: 'User', optional: true
      end
    rescue => e
      Rails.logger.warn "KC: TimeAccountingAgent prepended block failed: #{e.message}"
    end

    def effective_agent
      aid = respond_to?(:agent_id) ? agent_id : nil
      aid ? (User.lookup(id: aid) || User.lookup(id: created_by_id)) : User.lookup(id: created_by_id)
    rescue => e
      Rails.logger.warn "KC: effective_agent failed: #{e.message}"
      nil
    end

    def effective_agent_name
      effective_agent&.fullname || '-'
    end
  end
end
