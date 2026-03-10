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

bundle exec rails zammad:setup:auto_wizard

echo "== Rebuild search index =="

bundle exec rails zammad:searchindex:rebuild

echo "== Precompile frontend assets =="

bundle exec rails assets:precompile
