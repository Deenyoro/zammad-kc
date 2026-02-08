# frozen_string_literal: true

# KC Overlay: Forces ticket title rewriter to always generate English titles.
#
# The upstream instruction says "preserve the original input language" but
# the AI model often ignores this and generates random languages. This
# override explicitly requires English output.
module Kc::TicketTitleRewriterEnglish
  extend ActiveSupport::Concern

  def instruction
    "Stick to the following principles:

- Always generate the title in English, regardless of the input language.
- Summarize the provided content and come up with a suitable title.
- Try to use a maximum of 50 characters.
- Never explain your given answer.
- Only answer with the value in the \"title\" field inside the JSON structure."
  end
end
