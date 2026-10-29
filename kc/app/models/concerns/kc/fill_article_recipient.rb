# KC: Fills Ticket::Article#to for Teams, SMS and missed-call articles with
# who the message actually went to (see Kc::ArticleRecipients).
#
# For SMS and Teams articles the computed line replaces what the reply form
# sent: the delivery jobs never read `to` (they send to the conversation's
# participants), so the form's value could be a single number of a group
# text, or empty for Teams. Other articles (missed-call and capture notes)
# only get a `to` when they have none.
#
# Prepended by kc_loader.rb, so callbacks go in the `prepended` hook. A
# failure here only leaves `to` as it was; it never blocks the article.
module Kc
  module FillArticleRecipient
    extend ActiveSupport::Concern

    prepended do
      before_create :kc_fill_recipient
    rescue => e
      Rails.logger.warn "KC: FillArticleRecipient prepended block failed: #{e.message}"
    end

    private

    def kc_fill_recipient
      service = 'Kc::ArticleRecipients'.safe_constantize
      return if service.nil?

      type_name = Ticket::Article::Type.lookup(id: type_id)&.name
      channel_type = service::SMS_TYPES.key?(type_name) || type_name == service::TEAMS_TYPE
      return if !channel_type && to.present?

      label = service.label_for(self)
      self.to = label.truncate(3000) if label.present?
    rescue => e
      Rails.logger.warn "KC: could not fill the recipient of a new article: #{e.message}"
    end
  end
end
