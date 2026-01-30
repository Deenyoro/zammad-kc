# KC: Register the `ringcentral_sms_message` article type for RingCentral SMS/MMS integration.
#
# Uses a distinct type name to avoid conflict with upstream `sms` type
# (which has 160-char limits and is tied to Twilio/MessageBird drivers).
#
# Safety:
#   - Idempotent via create_if_not_exists
#   - Skipped on fresh installs (system_init_done guard)
class CreateKcRingcentralSmsArticleType < ActiveRecord::Migration[7.0]
  def up
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::Article::Type.create_if_not_exists(
      name:          'ringcentral_sms_message',
      communication: true,
      updated_by_id: 1,
      created_by_id: 1,
    )
  end

  def down
    return if !Setting.exists?(name: 'system_init_done')

    Ticket::Article::Type.find_by(name: 'ringcentral_sms_message')&.destroy
  end
end
