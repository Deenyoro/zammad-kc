# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class Channel::EmailParser::ContentParser
  attr_reader :mail

  def initialize(mail)
    @mail = mail
  end

  def message_body_hash
    (body, content_type, sanitized_body_info) = Channel::EmailParser::MessageWalker.new(mail).process_message_body

    content_type = 'text/plain' if body.blank?

    {
      attachments:         collect_attachments,
      content_type:        content_type || 'text/plain',
      body:                body.presence || 'no visible content',
      sanitized_body_info: sanitized_body_info || {},
    }.with_indifferent_access
  end

  private

  def collect_attachments
    [
      *nonplaintext_body_as_attachment, # get raw HTML message as an attachment
      *gracefully_get_attachments # get all attachments, including body-as-attachment
    ]
  end

  def nonplaintext_body_as_attachment
    (raw_body, raw_content_type,) = Channel::EmailParser::MessageWalker.new(mail, raw_html: true).process_message_body

    return if raw_content_type != 'text/html' || raw_body.blank?

    html_part = mail.html_part || mail

    filename = html_part.filename.presence || 'message.html'

    headers_store = {
      'content-alternative' => true,
      'original-format'     => raw_content_type == 'text/html',
      'Mime-Type'           => raw_content_type,
      'Charset'             => html_part.charset,
    }.compact_blank

    [{
      data:        raw_body,
      filename:    filename,
      preferences: headers_store
    }]
  end

  def gracefully_get_attachments
    get_attachments(mail).flatten.compact
  rescue => e # Protect process to work with spam emails (see test/fixtures/mail15.box)
    raise e if (fail_count ||= 0).positive?

    (fail_count += 1) && retry
  end

  def get_attachments(part, attachments: [], parent: nil)
    return part.parts.map { |p| get_attachments(p, attachments:, parent: part) } if part.parts.any?
    return [] if skip_attachments?(part, parent)

    Channel::EmailParser::AttachmentParser.new(part, attachments).parse
  end

  def skip_attachments?(part, parent)
    part_in_visible_parts?(part) ||
      (part.content_type&.start_with?('text/plain') && !part.attachment?) ||
      (parent&.content_type&.start_with?('multipart/mixed') && part.content_type&.start_with?('text/html') && !part.attachment?)
  end

  def part_in_visible_parts?(part)
    [mail.text_part, mail.html_part].any? { |subpart| subpart&.body&.encoded == part.body.encoded }
  end
end
