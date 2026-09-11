# KC: Re-reads the RingCentral message store and files every text that is
# missing from Zammad.
#
# Run by hand after a capture gap (or after upgrading the capture logic):
#
#   Kc::BackfillRingcentralSmsJob.new.perform(days: 30, dry_run: true)   # plan only
#   Kc::BackfillRingcentralSmsJob.new.perform(days: 30)                  # apply
#
# Outbound texts (sent from the RC app) are attached to the conversation's
# most recent ticket — closed ones included — or, when the agent started the
# conversation and no ticket ever existed, a ticket is created (closed if the
# text is older than the thread window, so history does not flood the queue).
# Inbound texts go through the normal driver and are only created when their
# RC message id is unknown. Articles are backdated to the RC timestamp.
#
# Returns a summary hash; every decision is logged with the "KC RingCentral
# Backfill" prefix.
class Kc::BackfillRingcentralSmsJob < ApplicationJob
  include Kc::RingcentralAuthRecovery

  PER_PAGE  = 100
  MAX_PAGES = 200

  def perform(days: 30, dry_run: false, channel_id: nil, directions: %w[Outbound Inbound])
    summary = Hash.new(0)
    scope   = Channel.where(area: 'RingCentralSms::Account', active: true)
    scope   = scope.where(id: channel_id) if channel_id.present?

    scope.find_each do |channel|
      backfill_channel(channel, days: days, dry_run: dry_run, directions: Array(directions), summary: summary)
    rescue StandardError => e
      Rails.logger.error "KC RingCentral Backfill: Failed for channel #{channel.id}: #{e.message}"
      summary[:channel_errors] += 1
    end

    Rails.logger.info "KC RingCentral Backfill: done#{' (dry run)' if dry_run} — #{summary.to_h.inspect}"
    summary.to_h
  end

  private

  def backfill_channel(channel, days:, dry_run:, directions:, summary:)
    rc_class = 'Kc::RingcentralApi'.safe_constantize
    return if rc_class.nil?

    rc         = rc_class.with_channel_tokens(channel)
    driver     = Channel::Driver::KcRingcentralSms.new
    poll_class = Kc::PollRingcentralSmsMessagesJob
    date_from  = days.to_i.days.ago.utc.iso8601

    directions.each do |direction|
      records = fetch_all(channel, rc, direction, date_from)
      Rails.logger.info "KC RingCentral Backfill: channel #{channel.id} #{direction}: #{records.size} messages since #{date_from}"

      records.each do |record|
        record = record.with_indifferent_access
        next unless %w[SMS Pager].include?(record[:type].to_s)

        message_data = poll_class.message_data_from_record(record, channel.options)

        if direction == 'Outbound'
          next if message_data[:to_phones].empty?

          plan = driver.outbound_capture_plan(channel, message_data, mode: :backfill)
          summary[:"outbound_#{plan[:action]}"] += 1
          if plan[:action] == :attach
            Rails.logger.info "KC RingCentral Backfill: #{dry_run ? 'would ' : ''}#{plan[:action]} #{message_data[:message_id]} " \
                              "#{message_data[:created_at]} to #{plan[:others].join(',')}" \
                              "#{plan[:ticket_id] ? " -> ticket #{plan[:ticket_id]}" : ''} " \
                              "#{message_data[:text].to_s.strip[0, 40].inspect} att=#{message_data[:attachments].size}"
            next if dry_run

            # Filing history must not surface the ticket as freshly updated in
            # every overview, nor stretch the thread window it is matched by.
            # Restore after the transaction: its commit hooks touch the ticket.
            previous_updated_at = Ticket.where(id: plan[:ticket_id]).pick(:updated_at)
            driver.process_outbound(channel.options, message_data, channel, mode: :backfill)
            if previous_updated_at
              Ticket.where(id: plan[:ticket_id]).update_all(updated_at: previous_updated_at) # rubocop:disable Rails/SkipsModelValidations
            end
          end
        else
          next if message_data[:from_phone].blank?

          known = Ticket::Article.exists?(message_id: "rc_sms:#{message_data[:message_id]}")
          summary[known ? :inbound_known : :inbound_create] += 1
          next if known

          Rails.logger.info "KC RingCentral Backfill: #{dry_run ? 'would ' : ''}create inbound #{message_data[:message_id]} " \
                            "#{message_data[:created_at]} from #{message_data[:from_phone]} " \
                            "#{message_data[:text].to_s.strip[0, 40].inspect}"
          driver.process(channel.options, message_data, channel) unless dry_run
        end
      rescue StandardError => e
        Rails.logger.error "KC RingCentral Backfill: Failed on #{record['id']}: #{e.message}"
        summary[:message_errors] += 1
      end
    end
  end

  # Whole window, oldest first, so conversation order is preserved.
  def fetch_all(channel, rc, direction, date_from)
    records = []
    page    = 1
    loop do
      result, _client = rc_call_with_auth_recovery(channel, 'KC RingCentral Backfill', client: rc) do |client|
        client.get_message_store(message_type: 'SMS', direction: direction, date_from: date_from, per_page: PER_PAGE, page: page)
      end
      break if result.nil?

      batch = result['records'] || result[:records] || []
      records.concat(batch)
      break if batch.size < PER_PAGE || page >= MAX_PAGES

      page += 1
    end
    records.sort_by { |m| (m['creationTime'] || m[:creationTime] || m['id']).to_s }
  end
end
