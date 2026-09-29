# KC: Detects HEIC/HEIF image data and converts it to JPEG.
#
# iPhones save photos as HEIC. Mail clients (Outlook mobile in particular)
# often attach them labelled "image/jpeg" with a .jpeg file name, so neither
# the MIME type nor the extension can be trusted. No browser renders HEIC and
# neither does Discord, which makes such images show up broken in the ticket
# and in every integration that forwards them.
#
# Detection reads the ISO BMFF "ftyp" box at the start of the data. Conversion
# uses Rszr (imlib2), which Zammad already ships for preview generation and
# which loads HEIC through libheif.
module Kc::HeicConverter
  # Major/compatible brands that mean HEVC-coded still images or sequences.
  # AVIF ("avif"/"avis") is left alone: browsers render it natively.
  HEIC_BRANDS  = %w[heic heix heim heis hevc hevx hevm hevs].freeze
  # Generic HEIF brands; only treated as HEIC when a HEIC brand is listed
  # among the compatible brands.
  HEIF_BRANDS  = %w[mif1 msf1].freeze
  JPEG_QUALITY = 90
  # Never try to decode absurdly large payloads inside a request.
  MAX_BYTES    = 50.megabytes

  module_function

  def heic?(data)
    return false if !data.is_a?(String) || data.bytesize < 12

    header = data.byteslice(0, 64).b
    return false if header.byteslice(4, 4) != 'ftyp'

    major = header.byteslice(8, 4)
    return true if HEIC_BRANDS.include?(major)
    return false if HEIF_BRANDS.exclude?(major)

    box_size   = header.byteslice(0, 4).unpack1('N').clamp(16, header.bytesize)
    compatible = header.byteslice(16, box_size - 16).to_s.scan(%r{.{4}}m)
    compatible.intersect?(HEIC_BRANDS)
  end

  # Returns JPEG data as a binary string, or nil when the data is not HEIC or
  # cannot be converted. Never raises.
  def to_jpeg(data)
    return if !heic?(data)
    return if data.bytesize > MAX_BYTES

    Dir.mktmpdir('kc-heic') do |dir|
      source = File.join(dir, 'source.heic')
      target = File.join(dir, 'target.jpg')
      File.binwrite(source, data)

      image = Rszr::Image.load(source)
      image.format = 'jpeg'
      image.save(target, quality: JPEG_QUALITY)

      jpeg = File.binread(target)
      jpeg.start_with?("\xFF\xD8".b) ? jpeg : nil
    end
  rescue => e
    Rails.logger.warn "KC HEIC: conversion failed, keeping original data: #{e.class}: #{e.message}"
    nil
  end

  def jpeg_filename(filename)
    name = filename.to_s
    return name if name.match?(%r{\.jpe?g\z}i)
    return name.sub(%r{\.hei[cf]s?\z}i, '.jpg') if name.match?(%r{\.hei[cf]s?\z}i)

    "#{name}.jpg"
  end

  # Returns a copy of the store preferences describing a JPEG. Keeps every
  # unrelated key (Content-ID, Content-Disposition, ...) untouched.
  def jpeg_preferences(preferences, filename)
    prefs = (preferences || {}).to_h.dup

    prefs.each_key do |key|
      case key.to_s.downcase
      when 'mime-type', 'mime_type'
        prefs[key] = 'image/jpeg'
      when 'content-type', 'content_type'
        prefs[key] = prefs[key].to_s.include?('name=') ? "image/jpeg; name=#{filename}" : 'image/jpeg'
      end
    end

    if prefs.keys.none? { |key| %w[mime-type mime_type content-type content_type].include?(key.to_s.downcase) }
      prefs['Mime-Type'] = 'image/jpeg'
    end

    prefs
  end
end
