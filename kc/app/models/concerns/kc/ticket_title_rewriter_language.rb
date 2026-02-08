# frozen_string_literal: true

# KC Overlay: Override ticket title rewriter to use configured default language.
#
# Problem: The upstream instruction says "preserve the original input language"
# but AI models often ignore this and generate titles in random languages.
#
# Solution: This overlay reads kc_ai_default_language setting and explicitly
# instructs the AI to use that language. Falls back to upstream behavior if
# the setting is missing or empty.
#
# Hardening:
#   - Safe Setting.get with rescue (survives if Setting class changes)
#   - Validates language code against known list
#   - Falls back gracefully to upstream behavior on any error
module Kc::TicketTitleRewriterLanguage
  extend ActiveSupport::Concern

  LANGUAGE_NAMES = {
    'en'    => 'English',
    'es'    => 'Spanish',
    'fr'    => 'French',
    'de'    => 'German',
    'pt-br' => 'Portuguese (Brazilian)',
    'ar'    => 'Arabic',
    'zh'    => 'Chinese',
    'ja'    => 'Japanese',
    'ko'    => 'Korean',
    'it'    => 'Italian',
    'nl'    => 'Dutch',
    'ru'    => 'Russian',
  }.freeze

  def instruction
    language_name = kc_resolve_language_name

    language_instruction = if language_name
                             "- Always generate the title in #{language_name}, regardless of the input language."
                           else
                             '- Always preserve the original input language (do not translate).'
                           end

    <<~INSTRUCTION.strip
      Stick to the following principles:

      #{language_instruction}
      - Summarize the provided content and come up with a suitable title.
      - Try to use a maximum of 50 characters.
      - Never explain your given answer.
      - Only answer with the value in the "title" field inside the JSON structure.
    INSTRUCTION
  end

  private

  # Safely retrieve the configured language name.
  # Returns nil if setting is missing, empty, or invalid.
  def kc_resolve_language_name
    return nil unless defined?(Setting)

    language_code = Setting.get('kc_ai_default_language')
    return nil if language_code.blank?

    LANGUAGE_NAMES[language_code.to_s.strip]
  rescue StandardError => e
    Rails.logger.warn("KC: Failed to read kc_ai_default_language setting: #{e.message}")
    nil
  end
end
