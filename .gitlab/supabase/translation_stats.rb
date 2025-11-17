#!/usr/bin/env ruby
# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require_relative 'supabase'

def translation_stats
  require 'poparser'

  Rails.root.glob('i18n/zammad.*.po').map do |file|
    po_entries = PoParser.parse_file(file).entries
    translated_count = po_entries.count(&:translated?)
    {
      locale:                         file.to_s.split('.')[-2],
      branch:                         ENV['CI_COMMIT_REF_NAME'],
      version:                        ENV['CI_COMMIT_REF_NAME'] == 'develop' ? '' : Version.get,
      strings:                        po_entries.count,
      strings_translated:             translated_count,
      translation_completion_percent: (translated_count * 100.0 / po_entries.count).to_i,
      test_data:                      ENV['SUPABASE_TEST'].present? || false,
    }
  end
end

def run
  if ENV['CI_COMMIT_REF_NAME'].blank?
    puts 'The required environment variable CI_COMMIT_REF_NAME is not set. Exiting.'
    exit 1
  end

  puts "Collecting translation stats for branch #{ENV['CI_COMMIT_REF_NAME']}…"
  payload = translation_stats
  puts 'Done.'

  puts 'Submitting to supabase…'
  Supabase.submit('zammad_translation_stats', payload)
  puts 'Done.'
end

run
