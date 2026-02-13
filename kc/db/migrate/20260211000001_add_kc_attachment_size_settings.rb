# frozen_string_literal: true

# KC: Add configurable attachment size limit for Teams Chat.
#
# Replaces the hardcoded MAX_ATTACHMENT_BYTES (5 MB) in the Teams driver
# with a configurable setting. Files larger than this limit are linked
# (via SharePoint URL) rather than downloaded into memory.
#
# Safety:
#   - Guarded by system_init_done check
#   - Idempotent via create_if_not_exists
class AddKcAttachmentSizeSettings < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'Teams Attachment Max Size (MB)',
      name:        'kc_teams_attachment_max_mb',
      area:        'Kc::General',
      description: 'Maximum file size (in MB) for Teams Chat attachments to be downloaded and stored on tickets. Files larger than this are linked via SharePoint URL instead. Default: 5 MB.',
      options:     {
        form: [
          {
            display: 'Max Attachment Size (MB)',
            null:    false,
            name:    'kc_teams_attachment_max_mb',
            tag:     'input',
            type:    'number',
          },
        ],
      },
      state:       5,
      preferences: { permission: ['admin'] },
      frontend:    false,
    )
  end

  def down
    Setting.find_by(name: 'kc_teams_attachment_max_mb')&.destroy
  end
end
