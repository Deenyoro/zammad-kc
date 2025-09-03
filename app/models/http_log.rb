# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class HttpLog < ApplicationModel
  store :request
  store :response

  # See https://github.com/zammad/zammad/issues/2100
  before_save :messages_to_utf8

=begin

cleanup old http logs

  HttpLog.cleanup

optional you can put the max oldest chat entries as argument

  HttpLog.cleanup(1.month)

=end

  def self.cleanup(diff = 1.month)
    where(created_at: ...diff.ago)
      .delete_all

    true
  end

  # Provide a mapping of facilities to required permissions as a function to be easily extendable in custom devs.
  def self.facilities_permission_lookup
    {
      'AI::Provider'       => 'admin.ai_provider',
      'check_mk'           => 'admin.integration',
      'clearbit'           => 'admin.integration',
      'cti'                => 'admin.integration',
      'EWS'                => 'admin.integration',
      'GitHub'             => 'admin.integration',
      'GitLab'             => 'admin.integration',
      'idoit'              => 'admin.integration',
      'ldap'               => 'admin.integration',
      'PGP'                => 'admin.integration',
      'placetel'           => 'admin.integration',
      'S/MIME'             => 'admin.integration',
      'SAML'               => 'admin.security',
      'sipagte.io'         => 'admin.integration', # typo in facility name, keep for backward compatibility
      'sipgate.io'         => 'admin.integration',
      'webhook'            => 'admin.webhook',
      'WhatsApp::Business' => 'admin.channel_whatsapp',
    }
  end

  # Make sure facility is valid if given.
  validates :facility, inclusion: { in: ->(_) { HttpLog.facilities_permission_lookup.keys } }

  def self.facility_to_permission(facility)
    return 'admin.*' if facility.blank?

    return facilities_permission_lookup[facility] if facilities_permission_lookup.key?(facility)

    nil
  end

  def self.facilities_by_permission
    @facilities_by_permission ||= facilities_permission_lookup
      .group_by { |_, permission| permission }
      .transform_values { |values| values.map { |facility, _| facility } }
  end

  private

  def messages_to_utf8
    request.transform_values! { |v| v.try(:utf8_encode) || v }
    response.transform_values! { |v| v.try(:utf8_encode) || v }
  end
end
