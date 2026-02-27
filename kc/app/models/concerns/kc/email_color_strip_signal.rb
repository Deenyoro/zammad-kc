# KC: Per-email bypass for the text color stripping feature.
#
# When an agent uses "Send with text color" in the Update dropdown, the
# frontend sets `article.preferences.kc_preserve_text_color = true` on the
# ticket update request.
#
# This concern wraps TicketArticleCommunicateEmailJob#perform to read that
# preference and set a thread-local flag that Kc::StripEmailTextColor checks.
#
# Thread-local is safe because each ActiveJob execution runs in its own
# thread context — the flag cannot leak to other jobs.
#
# HARDENING:
#   - Thread-local is always cleared in `ensure` block
#   - If the preference key is missing, defaults to false (strip as normal)
#   - If anything fails, thread-local is still cleared

module Kc
  module EmailColorStripSignal
    extend ActiveSupport::Concern

    def perform(article_id)
      record = Ticket::Article.find_by(id: article_id)

      if record&.preferences&.dig('kc_preserve_text_color')
        Thread.current[:kc_preserve_text_color] = true
      end

      super
    ensure
      Thread.current[:kc_preserve_text_color] = nil
    end
  end
end
