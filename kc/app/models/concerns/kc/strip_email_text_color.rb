# KC: Strip inline CSS `color:` properties from outbound email HTML.
#
# PROBLEM:
# Agents paste credentials into Zammad articles with inline CSS like
# style="color:rgb(237, 237, 237);" (near-white). This looks fine in Zammad's
# dark UI but is invisible in email clients with white backgrounds.
#
# FIX:
# Wrap Channel::EmailBuild.html_complete_check to strip the CSS `color:`
# property from all inline style attributes after the upstream method has
# built the complete HTML document.
#
# The regex `(?<!\w|-)color\s*:\s*[^";]+;?` strips `color:` but NOT
# `background-color:`, `border-color:`, etc. — the negative lookbehind
# ensures the `color` keyword is not preceded by a word character or hyphen.
#
# CONTROLS:
#   - Setting `kc_strip_email_text_color` (default true) — global toggle
#   - Thread.current[:kc_preserve_text_color] — per-email bypass set by
#     Kc::EmailColorStripSignal when agent uses "Send with text color"
#
# HARDENING:
#   - Calls super first, so upstream behavior is always preserved
#   - If regex fails or setting is missing, returns unmodified HTML
#   - Only strips from `style="..."` attribute values, not from other content
#   - Channel::EmailBuild is a module with singleton methods, so this must be
#     prepended onto `Channel::EmailBuild.singleton_class`

module Kc
  module StripEmailTextColor
    extend ActiveSupport::Concern

    def html_complete_check(html)
      result = super

      return result unless Setting.get('kc_strip_email_text_color')
      return result if Thread.current[:kc_preserve_text_color]

      strip_inline_text_color(result)
    rescue => e
      Rails.logger.warn "KC: StripEmailTextColor error: #{e.message}"
      result || html
    end

    private

    def strip_inline_text_color(html)
      # Match style="..." attributes and remove the `color:` property from each.
      # The outer regex finds style attribute values; the inner regex strips
      # the `color:` property while preserving other CSS properties.
      html.gsub(/style="([^"]*)"/) do |match|
        style_value = Regexp.last_match(1)

        # Strip `color:...` but not `background-color:`, `border-color:`, etc.
        # Negative lookbehind ensures `color` is not preceded by a word char or hyphen.
        cleaned = style_value.gsub(/(?<!\w|-)color\s*:\s*[^";]+;?\s*/, '')

        # Remove leading/trailing semicolons and whitespace
        cleaned = cleaned.strip.gsub(/\A;+\s*/, '').gsub(/;+\s*\z/, '').strip

        if cleaned.empty?
          # Remove the entire style attribute if nothing remains
          ''
        else
          "style=\"#{cleaned}\""
        end
      end
    end
  end
end
