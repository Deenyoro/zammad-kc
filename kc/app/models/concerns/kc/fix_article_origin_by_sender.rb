# KC: Fixes Zammad bug where origin_by_id incorrectly forces sender to Customer.
#
# Zammad's AddsMetadataGeneral concern has a bug on line 56:
#   return if origin_by == created_by_id
#
# This compares a User object (origin_by) to an integer (created_by_id),
# which always evaluates to false, causing sender to be forced to Customer
# whenever origin_by_id is set (even when it equals created_by_id).
#
# This concern overrides the buggy method to use the correct comparison:
#   return if origin_by_id == created_by_id
#
# This fix allows agents to set origin_by_id for attribution without
# breaking the sender field, which is critical for Teams/SMS delivery
# (the communicate jobs only fire for sender=Agent articles).
module Kc
  module FixArticleOriginBySender
    extend ActiveSupport::Concern

    prepended do
      # Override the buggy callback with our fixed version
      skip_callback :create, :before, :ticket_article_add_metadata_general, raise: false
      before_create :kc_ticket_article_add_metadata_general
    end

    private

    TYPE_NO_METADATA = %w[
      email
      facebook\ feed\ post
      facebook\ feed\ comment
      sms
      whatsapp\ message
    ].freeze

    def kc_ticket_article_add_metadata_general
      return if !neither_importing_nor_postmaster?
      return if !kc_type_uses_metadata_general?

      kc_metadata_general_process_origin_by

      return if author.blank?

      kc_metadata_general_process_from
    end

    def kc_type_uses_metadata_general?
      return if type_id.blank?

      type = Ticket::Article::Type.lookup(id: type_id)
      return if TYPE_NO_METADATA.include?(type.name)

      true
    end

    def kc_metadata_general_process_origin_by
      return if origin_by_id.blank?

      # In case a customer is using origin_by_id, force it to current session user
      if !created_by.permissions?('ticket.agent')
        self.origin_by_id = created_by_id
        self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
        return
      end

      # FIXED: Compare IDs, not User object to integer
      # Original Zammad bug: return if origin_by == created_by_id
      return if origin_by_id == created_by_id

      # If origin_by is different from created_by, set sender to Customer
      self.sender = Ticket::Article::Sender.lookup(name: 'Customer')
    end

    def kc_metadata_general_process_from
      type        = Ticket::Article::Type.lookup(id: type_id)
      is_customer = !author.permissions?('ticket.agent')
      fullname    = author.fullname(email_fallback: false).presence

      self.from = if %w[web phone].include?(type.name) && is_customer && author.email.present?
                    Channel::EmailBuild.recipient_line(fullname, author.email)
                  else
                    fullname
                  end
    end
  end
end
