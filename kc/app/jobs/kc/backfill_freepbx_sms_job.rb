# KC: Re-files a gap in FreePBX text messages from the PBX's message store.
#
# Usage (rails runner / console):
#   Kc::BackfillFreepbxSmsJob.new.perform(days: 7, dry_run: true)   # plan only
#   Kc::BackfillFreepbxSmsJob.new.perform(days: 7)                  # write
#
# Inbound texts go through the driver as usual (message-id dedup makes it
# safe to re-run); outbound texts are captured as notes in :backfill mode,
# which may attach to a closed ticket and keeps triggers and notifications
# quiet. Returns per-channel counts.
class Kc::BackfillFreepbxSmsJob < ApplicationJob
  def perform(days: 7, dry_run: false, channel: nil)
    poll_class = 'Kc::PollFreepbxSmsMessagesJob'.safe_constantize
    api_class  = 'Kc::FreepbxApi'.safe_constantize
    raise 'FreePBX SMS classes not available' if poll_class.nil? || api_class.nil?

    channels = channel ? [channel] : Channel.where(area: 'Freepbx::Account', active: true).order(:id).to_a
    driver   = Channel::Driver::KcFreepbx.new
    report   = {}

    channels.each do |ch|
      counts = Hash.new(0)
      begin
        messages = api_class.for_channel(ch).sms_messages(since_minutes: days.to_i * 24 * 60, limit: 5000)
                            .map(&:with_indifferent_access)
                            .sort_by { |m| (m[:created_at] || m[:time] || m[:id]).to_s }
      rescue StandardError => e
        Rails.logger.error "KC FreePBX SMS Backfill: could not read channel #{ch.id}: #{e.message}"
        report[ch.id] = { error: e.message }
        next
      end

      messages.each do |message|
        data = poll_class.message_data_from_record(message, ch.options)
        if data[:direction] == 'outbound'
          plan = driver.process_outbound(ch.options, data, ch, mode: :backfill, dry_run: dry_run)
          counts[dry_run ? plan[:action] : (plan ? :captured : :skipped)] += 1
        elsif dry_run
          exists = Ticket::Article.exists?(message_id: "#{Channel::Driver::KcFreepbx::DEDUP_PREFIX}#{data[:message_id]}")
          counts[exists ? :skip_known : :would_file] += 1
        else
          counts[driver.process(ch.options, data, ch) ? :filed : :skip_known] += 1
        end
      rescue StandardError => e
        counts[:failed] += 1
        Rails.logger.error "KC FreePBX SMS Backfill: message #{message[:id]} failed: #{e.message}"
      end

      report[ch.id] = counts
    end

    report
  end
end
