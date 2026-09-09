# KC: Keep OAuth secrets written by the KC channel flows out of the browser.
#
# Channel#assets masks the paths listed in Channel::SENSITIVE_FIELDS before
# the record is pushed to the Spine collection. Upstream lists the paths its
# own channels use; the KC RingCentral SMS and Teams Chat channels store
# their OAuth credentials at options.client_secret / options.refresh_token /
# options.access_token, which upstream does not mask. Without this every
# admin page load shipped a long-lived refresh token and the app secret to
# the client.
#
# No KC frontend reads these values — the edit modals only expose group,
# thread window, cutoff date and phone number — so masking is safe.
module Kc
  module ChannelSensitiveFields
    extend ActiveSupport::Concern

    KC_SENSITIVE_FIELDS = %w[
      options.client_secret
      options.refresh_token
      options.access_token
    ].freeze

    def sensitive_attributes(input, object)
      (Array(super) + KC_SENSITIVE_FIELDS).uniq
    end
  end
end
