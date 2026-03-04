# KC: Pass the article BCC value to the email delivery layer via thread-local.
#
# The email job builds an attr hash for Channel#deliver but does not include
# bcc. Rather than monkey-patching the hash construction, we set a
# thread-local that Kc::EmailOutboundBcc reads in prepare_bcc_header.
#
# Thread-local is safe because each ActiveJob execution runs in its own
# thread context — the flag cannot leak to other jobs.

module Kc
  module EmailJobBcc
    extend ActiveSupport::Concern

    def perform(article_id)
      record = Ticket::Article.find_by(id: article_id)

      if record&.bcc.present?
        Thread.current[:kc_article_bcc] = record.bcc
      end

      super
    ensure
      Thread.current[:kc_article_bcc] = nil
    end
  end
end
