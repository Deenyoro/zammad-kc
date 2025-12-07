# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Text::QuoteRemover, :aggregate_failures do
  shared_examples 'when quote remover is executed' do |fixture_path|
    context "with #{fixture_path.basename}" do
      let(:input_text)          { File.read(fixture_path) }
      let(:expected_text)       { File.read(fixture_path.to_s.sub('-input.txt', '-expected.txt')) }

      let(:email_remove_quote_execution) { described_class.new(text: input_text).remove }

      it 'removes the quoted parts' do
        sanitized_text = email_remove_quote_execution

        expect(sanitized_text).to eq(expected_text)
      end
    end
  end

  fixture_path = 'spec/fixtures/files/text/quote_remover/'

  fixture_files = if ENV['REMOVE_QUOTE_RESULT_INPUT_FILE']
                    [Rails.root.join("#{fixture_path}#{ENV['REMOVE_QUOTE_RESULT_INPUT_FILE']}")]
                  else
                    Rails.root.glob("#{fixture_path}*-input.txt")
                  end

  context 'when files are checked' do
    fixture_files.each do |fixture_path|
      include_examples 'when quote remover is executed', fixture_path
    end
  end
end
