# KC: Converts HEIC/HEIF images to JPEG at the moment they are stored.
#
# PROBLEM:
# iPhone photos arrive as HEIC, frequently mislabelled as image/jpeg (ticket
# 7333: "original-….jpeg" from Outlook mobile was really HEIC). Browsers and
# Discord cannot render HEIC, so the image shows as broken everywhere.
#
# FIX:
# Every attachment passes through Store#set_store_file, whatever its origin
# (email, web upload, SMS/MMS, Teams, API). The override sniffs the data and,
# when it is HEIC, stores a JPEG instead and corrects file name and MIME
# preferences. Content-ID is preserved, so inline references keep working.
# Upstream preview generation then runs on the JPEG as for any other image.
#
# HARDENING:
# 1. Anything that is not HEIC goes straight to super, byte for byte.
# 2. A failed conversion keeps the original data (logged, never raised).
# 3. Skipped in import mode, like upstream preview generation.
# 4. If upstream renames set_store_file the override is simply never called
#    and attachments are stored unconverted; Kc::ConvertHeicAttachmentsJob
#    can still convert them afterwards.
module Kc::StoreHeicConversion
  extend ActiveSupport::Concern

  def set_store_file
    kc_convert_heic_data
    super
  end

  private

  def kc_convert_heic_data
    return if Setting.get('import_mode')

    jpeg = Kc::HeicConverter.to_jpeg(data)
    return if jpeg.blank?

    original_size = data.bytesize
    self.data        = jpeg
    self.filename    = Kc::HeicConverter.jpeg_filename(filename)
    self.preferences = Kc::HeicConverter.jpeg_preferences(preferences, filename)

    Rails.logger.info "KC HEIC: converted '#{filename}' to JPEG (#{original_size} -> #{jpeg.bytesize} bytes)"
  rescue => e
    Rails.logger.warn "KC HEIC: skipped conversion for '#{filename}': #{e.class}: #{e.message}"
  end
end
