# KC: ActiveRecord model for scheduled articles.
#
# Stores reply data that an agent wants to send at a future time.
# A background job polls for due records and creates real Ticket::Article
# records, which triggers the standard communication pipeline.
#
# article_data JSONB expected keys:
#   { body: string, type: string, sender: string, to: string?,
#     cc: string?, subject: string?, internal: bool?,
#     content_type: string?, form_id: integer?, preferences: hash? }
#
# Attachments: when a reply is scheduled, the selected files of the compose
# form's UploadCache are copied into Store items owned by this record
# (object 'Kc::ScheduledArticle', o_id = id) and form_id is dropped from
# article_data. The reply is sent from those copies, so files added to the
# form later (the new UI keeps one form id per tab) are never picked up and
# the monthly UploadCache purge cannot lose them. The copies are removed once
# the record leaves 'pending' (sent, cancelled or failed).
# Records scheduled before this change still carry a numeric legacy form_id
# and are sent from that UploadCache as before.
#
# ticket_attributes JSONB expected keys:
#   { state_id: integer?, priority_id: integer?, owner_id: integer?, ... }
#
# Safety:
#   - table_exists? guard so the app can boot before migration runs
#   - All associations and validations inside the guard
#   - Status validated against allowed values
#   - cancel! guards against non-pending status
class Kc::ScheduledArticle < ApplicationModel
  self.table_name = 'kc_scheduled_articles'

  VALID_STATUSES = %w[pending sent cancelled failed].freeze

  STORE_OBJECT = 'Kc::ScheduledArticle'.freeze

  if table_exists?
    belongs_to :ticket
    belongs_to :created_by, class_name: 'User'
    belongs_to :updated_by, class_name: 'User'

    validates :ticket_id,      presence: true
    validates :article_data,   presence: true
    validates :scheduled_at,   presence: true
    validates :created_by_id,  presence: true
    validates :updated_by_id,  presence: true
    validates :status,         presence: true, inclusion: { in: VALID_STATUSES }

    scope :pending, -> { where(status: 'pending') }

    # Use CURRENT_TIMESTAMP in SQL to avoid stale Ruby Time.current
    scope :due,     -> { where(status: 'pending').where('scheduled_at <= CURRENT_TIMESTAMP') }

    # Stored attachment copies are only needed while the reply is pending.
    after_commit :remove_stored_attachments, on: :update, if: -> { saved_change_to_status? && status != 'pending' }

    # Store items holding the attachments of this scheduled reply.
    def stored_attachments
      Store.list(object: STORE_OBJECT, o_id: id)
    end

    # Copies the attachments of a compose form's UploadCache into Store items
    # owned by this record.
    #
    # @param form_id [String, Integer] form id of the compose form (UUID in
    #   the new UI, numeric in the legacy UI)
    # @param files [Array<Hash>, nil] the files selected in the form
    #   ({ name:, type: }); nil copies every non-inline file of the form
    #   (legacy UI, where the cache only holds the reply's own files)
    # @param user_id [Integer] owner of the UploadCache items
    # @return [Array<Store>] the created Store items
    def store_attachments_from_form!(form_id, files:, user_id:)
      return [] if form_id.blank?

      UploadCache.new(form_id).attachments(created_by_id: user_id).filter_map do |att|
        next if att.inline?
        next if !files.nil? && !UploadCache.files_include_attachment?(files, att)

        Store.create!(
          object:        STORE_OBJECT,
          o_id:          id,
          data:          att.content,
          filename:      att.filename,
          preferences:   att.preferences,
          created_by_id: user_id,
        )
      end
    end

    # Copies the stored attachments (or, for records scheduled before stored
    # copies existed, the legacy form's UploadCache files) into another
    # UploadCache, so "Edit" can put them back into the compose form.
    #
    # @return [Array<Store>] the created UploadCache items
    def restore_attachments_to_form!(form_id, user_id:)
      return [] if form_id.blank?

      sources = stored_attachments.to_a
      legacy_form_id = article_data&.dig('form_id')
      if sources.empty? && legacy_form_id.present? && legacy_form_id.to_s.match?(%r{\A\d+\z})
        legacy_files = UploadCache.new(legacy_form_id.to_i).attachments(created_by_id: created_by_id).reject(&:inline?)
        # Same form: the files are already there (cancel! must keep them).
        return legacy_files if legacy_form_id.to_s == form_id.to_s

        sources = legacy_files
      end

      cache = UploadCache.new(form_id)
      sources.map do |att|
        cache.add(
          data:          att.content,
          filename:      att.filename,
          preferences:   att.preferences,
          created_by_id: user_id,
        )
      end
    end

    def remove_stored_attachments
      Store.remove(object: STORE_OBJECT, o_id: id)
    rescue => e
      Rails.logger.warn "KC: Attachment cleanup failed for scheduled article ##{id}: #{e.message}"
    end

    # Cancel a scheduled article before it is sent.
    # Stored attachment copies are removed by the after_commit hook; a legacy
    # form_id cache (records scheduled before stored copies) is removed here.
    # @param cancelled_by_id [Integer] the user who is cancelling (for audit trail)
    # @param keep_legacy_form_cache [Boolean] keep the legacy form_id cache
    #   (its files were just restored into the compose form)
    def cancel!(cancelled_by_id: nil, keep_legacy_form_cache: false)
      raise "Cannot cancel scheduled article ##{id} with status '#{status}'" unless status == 'pending'

      by_id = cancelled_by_id || UserInfo.current_user_id || updated_by_id
      update!(status: 'cancelled', updated_by_id: by_id)

      # Best-effort cleanup — don't fail cancellation if cache is already gone
      form_id = article_data&.dig('form_id')
      if !keep_legacy_form_cache && form_id.present? && form_id.to_s.match?(/\A\d+\z/) && defined?(UploadCache)
        UploadCache.new(form_id.to_i).destroy
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "KC: Failed to cancel scheduled article #{id}: #{e.message}"
      raise
    rescue RuntimeError
      # Re-raise status guard errors
      raise
    rescue => e
      # Log but don't re-raise for UploadCache cleanup failures —
      # the status update already succeeded if we got past update!
      Rails.logger.warn "KC: UploadCache cleanup failed for scheduled article #{id}: #{e.message}"
    end
  end
rescue => e
  Rails.logger.warn "KC: ScheduledArticle class body failed: #{e.message}"
end
