# KC: Inject article-level BCC into the outbound email attr hash.
#
# The upstream prepare_bcc_header only handles system_bcc from Settings.
# This concern reads the thread-local set by Kc::EmailJobBcc and injects
# the article's BCC recipients before calling super (which appends system_bcc).
#
# The Mail gem handles BCC correctly per RFC 5322 — removes from visible
# headers and delivers to all BCC recipients.

module Kc
  module EmailOutboundBcc
    extend ActiveSupport::Concern

    private

    def prepare_bcc_header(attr)
      article_bcc = Thread.current[:kc_article_bcc]

      if article_bcc.present?
        attr[:bcc] ||= ''
        attr[:bcc] += ', ' if attr[:bcc].present?
        attr[:bcc] += article_bcc
      end

      super
    end
  end
end
