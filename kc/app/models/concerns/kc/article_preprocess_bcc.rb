# KC: Extend Service::Ticket::Article::Create to preprocess the :bcc field
# the same way :to and :cc are handled — join arrays to comma-separated
# strings and default to empty string.

module Kc
  module ArticlePreprocessBcc
    extend ActiveSupport::Concern

    private

    def preprocess_to_cc(article_data)
      super

      article_data[:bcc] = article_data[:bcc].join(', ') if article_data[:bcc].is_a?(Array)
      article_data[:bcc] ||= ''
    end
  end
end
