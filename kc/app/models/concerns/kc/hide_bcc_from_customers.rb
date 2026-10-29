# KC: Keeps an article's Bcc (the kc bcc column) away from customers.
#
# The REST article endpoints and the legacy UI's assets serialize articles
# with attributes_with_association_names / assets, which end in
# filter_unauthorized_attributes. Upstream already strips agent-only fields
# there for non-agents (detected_language); Bcc is hidden recipients by
# definition, so a customer reading their own ticket must not see it.
# GraphQL never exposed it to customers.
#
# Prepended into Ticket::Article by kc_loader.rb.
module Kc
  module HideBccFromCustomers
    def filter_unauthorized_attributes(attributes)
      result = super
      return result if UserInfo.assets.agent?

      result.except('bcc')
    end
  end
end
