# KC: Add a global default language setting for all AI-generated content.
#
# This setting allows administrators to specify the language that AI
# features should use when generating content (titles, summaries, etc.).
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcAiDefaultLanguageSetting < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Default AI Language',
      name:        'kc_ai_default_language',
      area:        'AI::Assistance',
      description: 'The default language for all AI-generated content (ticket titles, summaries, suggestions, etc.). When set, AI will generate content in this language regardless of the input language.',
      options:     {
        form: [
          {
            display:   'Default Language',
            null:      true,
            name:      'kc_ai_default_language',
            tag:       'select',
            options:   {
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
        permission: ['admin.ai'],
      },
      frontend:    true,
    )
  end

  def down
    Setting.find_by(name: 'kc_ai_default_language')&.destroy
  end
end
