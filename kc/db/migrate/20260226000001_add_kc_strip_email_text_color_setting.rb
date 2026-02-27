# KC: Add setting to auto-strip inline text color from outbound emails.
#
# Agents often paste credentials with near-white text (e.g. color:rgb(237,237,237))
# that looks fine in Zammad's dark UI but is invisible in email clients with
# white backgrounds.
#
# Safety:
#   - Idempotent via create_if_not_exists
class AddKcStripEmailTextColorSetting < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Strip Inline Text Color from Outbound Emails',
      name:        'kc_strip_email_text_color',
      area:        'Kc::General',
      description: 'When enabled, inline CSS color: properties are automatically stripped from outbound email HTML. This prevents near-white text (pasted from dark UIs) from being invisible in email clients with white backgrounds. Agents can override per-email via the "Send with text color" dropdown item.',
      options:     {
        form: [
          {
            display:  'Strip inline text color',
            null:     true,
            name:     'kc_strip_email_text_color',
            tag:      'boolean',
            options:  {
              true  => 'yes',
              false => 'no',
            },
          },
        ],
      },
      state:        true,
      preferences:  {},
      frontend:     true,
    )
  end

  def down
    Setting.find_by(name: 'kc_strip_email_text_color')&.destroy
  end
end
