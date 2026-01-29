# KC: Register the `teams_chat_message` article type for Microsoft Teams Chat integration.
#
# Safety:
#   - Idempotent via create_if_not_exists
#   - Skipped on fresh installs (system_init_done guard)
class CreateKcTeamsChatArticleType < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::Article::Type.create_if_not_exists(
      name:          'teams_chat_message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end

  def down
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::Article::Type.find_by(name: 'teams_chat_message')&.destroy
  end
end
