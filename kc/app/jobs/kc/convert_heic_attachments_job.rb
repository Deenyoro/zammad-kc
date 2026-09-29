# KC: Converts HEIC/HEIF attachments that were stored before
# Kc::StoreHeicConversion existed.
#
# Run by hand:
#
#   Kc::ConvertHeicAttachmentsJob.new.perform(dry_run: true)   # plan only
#   Kc::ConvertHeicAttachmentsJob.new.perform                  # apply
#   Kc::ConvertHeicAttachmentsJob.new.perform(store_ids: [22912])
#
# Candidates are attachments named or typed HEIC/HEIF, plus images for which
# Zammad could not build a preview (the telltale of a mislabelled HEIC). Each
# candidate is confirmed by its file signature before anything is changed.
#
# The original Store::File is only removed when no other attachment shares it.
# Returns a summary hash; every decision is logged with the "KC HEIC" prefix.
class Kc::ConvertHeicAttachmentsJob < ApplicationJob
  def perform(dry_run: false, days: nil, store_ids: nil)
    summary = Hash.new(0)

    candidates(days: days, store_ids: store_ids).find_each do |store|
      summary[:checked] += 1
      convert(store, dry_run: dry_run, summary: summary)
    rescue => e
      summary[:errors] += 1
      Rails.logger.error "KC HEIC: failed for store #{store.id}: #{e.class}: #{e.message}"
    end

    Rails.logger.info "KC HEIC: backfill done#{' (dry run)' if dry_run} — #{summary.to_h.inspect}"
    summary.to_h
  end

  private

  def candidates(days:, store_ids:)
    scope = Store.all
    scope = scope.where(id: store_ids) if store_ids.present?
    scope = scope.where(created_at: days.to_i.days.ago..) if days.present?
    return scope if store_ids.present?

    scope.where(
      "filename ILIKE '%.heic' OR filename ILIKE '%.heif' OR preferences ILIKE '%image/hei%' " \
      "OR (preferences ILIKE '%image/%' AND preferences NOT ILIKE '%content_preview%')"
    )
  end

  def convert(store, dry_run:, summary:)
    data = store.content
    if !Kc::HeicConverter.heic?(data)
      summary[:not_heic] += 1
      return
    end

    jpeg = Kc::HeicConverter.to_jpeg(data)
    if jpeg.blank?
      summary[:unconvertible] += 1
      Rails.logger.warn "KC HEIC: store #{store.id} ('#{store.filename}') is HEIC but could not be converted"
      return
    end

    Rails.logger.info "KC HEIC: #{dry_run ? 'would convert' : 'converting'} store #{store.id} ('#{store.filename}', #{data.bytesize} -> #{jpeg.bytesize} bytes)"
    summary[:converted] += 1
    return if dry_run

    replace_content(store, jpeg)
  end

  def replace_content(store, jpeg)
    old_file_id = store.store_file_id
    filename    = Kc::HeicConverter.jpeg_filename(store.filename)

    Store.transaction do
      store.update!(
        store_file_id: Store::File.add(jpeg).id,
        size:          jpeg.bytesize,
        filename:      filename,
        preferences:   Kc::HeicConverter.jpeg_preferences(store.preferences, filename),
      )
    end

    store.send(:generate_previews)

    return if Store.exists?(store_file_id: old_file_id)

    Store::File.find_by(id: old_file_id)&.destroy!
  end
end
