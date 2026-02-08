# frozen_string_literal: true

# KC: Add a global default language setting for AI-generated content.
#
# This setting allows administrators to specify the language that AI
# features should use when generating content (titles, summaries, etc.).
#
# Safety:
#   - Guarded by system_init_done check
#   - Idempotent via create_if_not_exists
#   - Safe destroy in down migration
class AddKcAiDefaultLanguageSetting < ActiveRecord::Migration[7.0]
  def up
    # Guard: only run after Zammad is fully initialized
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Default Language for AI Content',
      name:        'kc_ai_default_language',
      area:        'Kc::General',
      description: 'The default language for AI-generated content (ticket titles, summaries, suggestions). When set, content is generated in this language regardless of input language. Leave empty to auto-detect.',
      options:     {
        form: [
          {
            display: 'Default Language',
            null:    true,
            name:    'kc_ai_default_language',
            tag:     'select',
            options: {
              ''       => '- Auto-detect (preserve input language) -',
              'en'     => 'English',
              'es'     => 'Spanish',
              'fr'     => 'French',
              'de'     => 'German',
              'pt-br'  => 'Portuguese (Brazilian)',
              'ar'     => 'Arabic',
              'zh'     => 'Chinese',
              'ja'     => 'Japanese',
              'ko'     => 'Korean',
              'it'     => 'Italian',
              'nl'     => 'Dutch',
              'ru'     => 'Russian',
            },
          },
        ],
      },
      state:       'en',
      preferences: {
        permission: ['admin'],
      },
      frontend:    true,
    )
  end

  def down
    Setting.find_by(name: 'kc_ai_default_language')&.destroy
  end
end
