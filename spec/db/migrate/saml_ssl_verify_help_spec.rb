# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe SamlSSLVerifyHelp, type: :db_migration do
  before do
    setting = Setting.find_by(name: 'auth_saml_credentials')

    setting.options[:form].each do |o|
      next if !o[:name].eql?('ssl_verify')

      o[:help] = 'Turning off SSL verification is a security risk and should be used only temporary. Use this option at your own risk!'
    end

    setting.save!
  end

  it 'updates the help text' do
    migrate

    expect(Setting.find_by(name: 'auth_saml_credentials').options[:form].find { |o| o[:name] == 'ssl_verify' }[:help]).to eq('Verification of the TLS connection to the IDP SSO target URL. Only relevant during setting up SAML authentication.')
  end
end
