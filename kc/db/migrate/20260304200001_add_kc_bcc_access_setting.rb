class AddKcBccAccessSetting < ActiveRecord::Migration[7.2]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Setting.create_if_not_exists(
      title:       'BCC Field Access',
      name:        'kc_bcc_access',
      area:        'Kc::General',
      description: 'Controls who can use the BCC field on email replies. "All agents" shows the field for everyone, "Admins only" restricts it to admin users, "Disabled" hides it entirely.',
      options:     {
        form: [
          {
            display:  'BCC Field Access',
            null:     false,
            name:     'kc_bcc_access',
            tag:      'select',
            options:  {
              'all'      => 'All agents',
              'admin'    => 'Admins only',
              'disabled' => 'Disabled',
            },
          },
        ],
      },
      state:       'all',
      preferences: { permission: ['admin'] },
      frontend:    true,
    )
  end

  def down
    Setting.find_by(name: 'kc_bcc_access')&.destroy
  end
end
