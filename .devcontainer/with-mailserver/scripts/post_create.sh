#!/usr/bin/env sh

env

# Ensure proper permissions on root-mounted volume.
sudo chown -R "${USER}" node_modules

bin/setup --skip-server

echo "== Precompile Ruby cache =="

bundle exec bootsnap precompile --gemfile app/ lib/

echo "== Configure Elasticsearch URL =="

bundle exec rails r "Setting.set('es_url', 'http://elasticsearch:9200')"

echo "== Run auto_wizard setup =="

bundle exec rails zammad:setup:auto_wizard[.devcontainer/with-mailserver/auto_wizard_mailserver.json]

CERT_PATH=.devcontainer/with-mailserver/certs/mail.test.local.crt

# Import self-signed certificate for mailserver.
if [ -f "$CERT_PATH" ]; then
  echo "== Import self-signed certificate for mailserver =="
  bundle exec rails r "SSLCertificate.create!(certificate: Rails.root.join('$CERT_PATH').read)"
fi

echo "== Rebuild search index =="

bundle exec rails zammad:searchindex:rebuild

echo "== Precompile frontend assets =="

bundle exec rails assets:precompile
