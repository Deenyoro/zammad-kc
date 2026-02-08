# frozen_string_literal: true

# KC Overlay: Forces ticket title rewriter to use the configured default language.
#
# The upstream instruction says "preserve the original input language" but
# the AI model often ignores this and generates random languages. This
# override uses the kc_ai_default_language setting to enforce a specific
# language, or falls back to the original behavior if not set.
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
    default_language = Setting.get('kc_ai_default_language').presence

    language_instruction = if default_language && LANGUAGE_NAMES[default_language]
                             "- Always generate the title in #{LANGUAGE_NAMES[default_language]}, regardless of the input language."
                           else
                             '- Always preserve the original input language (do not translate).'
                           end

    "Stick to the following principles:

#{language_instruction}
- Summarize the provided content and come up with a suitable title.
- Try to use a maximum of 50 characters.
- Never explain your given answer.
- Only answer with the value in the \"title\" field inside the JSON structure."
  end
end
