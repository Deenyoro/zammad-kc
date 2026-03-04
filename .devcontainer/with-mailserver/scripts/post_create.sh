#!/usr/bin/env sh

env

# Ensure proper permissions on root-mounted volume.
sudo chown -R "${USER}" node_modules

bin/setup --skip-server

bundle exec bootsnap precompile --gemfile app/ lib/

bundle exec rails r "Setting.set('es_url', 'http://elasticsearch:9200')"

bundle exec rails zammad:setup:auto_wizard[.devcontainer/with-mailserver/auto_wizard_mailserver.json]

CERT_PATH=.devcontainer/with-mailserver/certs/mail.test.local.crt

# Import self-signed certificate for mailserver.
if [ -f "$CERT_PATH" ]; then
  bundle exec rails r "SSLCertificate.create!(certificate: Rails.root.join('$CERT_PATH').read)"
fi
