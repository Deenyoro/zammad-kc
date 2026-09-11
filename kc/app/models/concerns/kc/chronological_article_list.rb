# KC: Show a ticket's articles in the order they happened.
#
# Upstream Service::Ticket::Article::List (the source of the desktop-view
# article feed) orders by id, i.e. by insertion. Every KC channel that backs
# up webhooks with polling (Teams, RingCentral SMS) can file a message after a
# newer one already arrived, and outbound texts sent from the RC/Teams apps
# are always captured after the fact. Those articles carry the real message
# timestamp in created_at, so ordering by it puts the conversation back in
# sequence; id breaks the tie for articles created in the same second.
#
# Prepended into Service::Ticket::Article::List by kc_loader.rb.
module Kc::ChronologicalArticleList
  extend ActiveSupport::Concern

  def execute
    relation = super
    return relation unless relation.respond_to?(:reorder)

    relation.reorder(:created_at, :id)
  rescue StandardError => e
    Rails.logger.warn "KC: ChronologicalArticleList failed, falling back to upstream order: #{e.message}"
    super
  end
end
