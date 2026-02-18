module Kc
  module SuppressInternalNoteNotifications
    extend ActiveSupport::Concern

    def article_by_item
      result = super
      return result if result.nil?

      if Setting.get('kc_suppress_internal_note_notifications') && result.internal?
        Rails.logger.debug { "KC: Suppressing notification for internal article ##{result.id} on ticket ##{result.ticket_id}" }
        return nil
      end

      if Setting.get('kc_suppress_all_note_notifications') && result.type&.name == 'note'
        Rails.logger.debug { "KC: Suppressing notification for note article ##{result.id} on ticket ##{result.ticket_id}" }
        return nil
      end

      result
    rescue => e
      Rails.logger.warn "KC: SuppressInternalNoteNotifications error: #{e.message}"
      result
    end
  end
end
