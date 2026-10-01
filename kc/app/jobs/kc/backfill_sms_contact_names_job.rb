# KC: Puts contact names on SMS tickets that were opened before names were
# looked up (Kc::PhoneContacts).
#
# Usage (rails runner / console):
#   Kc::BackfillSmsContactNamesJob.new.perform(dry_run: true)   # report only
#   Kc::BackfillSmsContactNamesJob.new.perform                  # write
#   Kc::BackfillSmsContactNamesJob.new.perform(users: true)     # also rename every placeholder customer
#
# Only tickets that are open now are touched: the bare number in the title
# becomes "Jane Smith (+14125550100)", the customer's texts show the same
# in their From, and a placeholder customer (named after the number) is
# renamed after the contact. Closed, merged and removed tickets are left
# exactly as they are. Triggers and notifications are off for every write.
#
# users: true additionally renames placeholder customers that have no open
# ticket. That changes no ticket, only the name shown for the customer.
class Kc::BackfillSmsContactNamesJob < ApplicationJob
  SMS_PREFS_KEYS    = %w[ringcentral_sms freepbx_sms].freeze
  SMS_ARTICLE_TYPES = %w[ringcentral_sms_message freepbx_sms_message].freeze
  DISPATCH_DISABLE  = ['Transaction::Trigger', 'Transaction::Notification'].freeze

  def perform(dry_run: false, users: false)
    contacts = 'Kc::PhoneContacts'.safe_constantize
    raise 'Kc::PhoneContacts not available' if contacts.nil?

    report = Hash.new(0)
    report[:tickets] = []

    open_sms_tickets.each do |ticket|
      backfill_ticket(contacts, ticket, dry_run, report)
    rescue => e
      report[:failed] += 1
      Rails.logger.error "KC SMS Contact Names: ticket #{ticket.id} failed: #{e.message}"
    end

    rename_placeholder_users(contacts, dry_run, report) if users
    report
  end

  private

  def open_sms_tickets
    closed_ids = Ticket::State
                   .joins(:state_type)
                   .where("ticket_state_types.name IN (?) OR ticket_states.name LIKE 'closed%'", %w[closed merged removed])
                   .pluck(:id)

    Ticket.where(SMS_PREFS_KEYS.map { 'preferences LIKE ?' }.join(' OR '), *SMS_PREFS_KEYS.map { |k| "%#{k}:%" })
          .where.not(state_id: closed_ids)
          .reorder(:id)
  end

  def backfill_ticket(contacts, ticket, dry_run, report)
    prefs  = (ticket.preferences || {}).with_indifferent_access
    sms    = SMS_PREFS_KEYS.filter_map { |key| prefs[key] }.first&.with_indifferent_access || {}
    number = contacts.normalize(sms[:from_phone])
    return if number.blank?

    customer = ticket.customer
    renamed  = contacts.placeholder?(customer) && same_number?(contacts, customer, number) &&
               (dry_run ? contacts.book_name_for(number).present? : contacts.enrich_placeholder(customer, number))
    name = contacts.name_for(number)
    if name.blank?
      report[:no_name] += 1
      return
    end

    display   = contacts.display(number, name: name)
    new_title = retitle(ticket.title.to_s, number, display)
    articles  = Ticket::Article.where(ticket_id: ticket.id, from: number,
                                      type_id: Ticket::Article::Type.where(name: SMS_ARTICLE_TYPES).select(:id))

    report[:tickets] << { id: ticket.id, number: ticket.number, title: [ticket.title, new_title].uniq,
                          customer_renamed: renamed, articles: articles.count }
    if dry_run
      report[:would_update] += 1
      return
    end

    Transaction.execute(disable: DISPATCH_DISABLE, reset_user_id: true) do
      ticket.update!(title: new_title, updated_by_id: 1) if new_title != ticket.title
      articles.find_each { |article| article.update!(from: display, updated_by_id: 1) }
    end
    report[:updated] += 1
  end

  # Swaps the bare number for "Name (number)" and leaves titles that no
  # longer carry the bare number (renamed by an agent) alone.
  def retitle(title, number, display)
    return title if title.include?(display) || title.exclude?(number)

    title.sub(number, display).truncate(100, omission: '...')
  end

  def same_number?(contacts, user, number)
    [user.phone, user.mobile].any? { |n| contacts.match_key(n).present? && contacts.match_key(n) == contacts.match_key(number) }
  end

  def rename_placeholder_users(contacts, dry_run, report)
    User.where(lastname: [nil, ''])
        .where("firstname ~ '^\\+?[0-9 ().-]{7,}$'")
        .find_each do |user|
      next if !contacts.placeholder?(user)

      number = user.phone.presence || user.mobile.presence
      next if number.blank?

      if dry_run
        report[:users_would_rename] += 1 if contacts.book_name_for(number).present?
      elsif contacts.enrich_placeholder(user, number)
        report[:users_renamed] += 1
      end
    end
  end
end
