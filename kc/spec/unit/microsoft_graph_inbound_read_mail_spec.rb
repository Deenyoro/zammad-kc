# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rspec'
require 'active_support/all'
require 'active_model'
require 'erb'
require 'set'

Time.zone = 'UTC'

module Kc; end

class Rails
  def self.logger
    @logger ||= Logger.new(nil)
  end

  def self.cache
    @cache ||= ActiveSupport::Cache::MemoryStore.new
  end

  def self.root
    Pathname.new(File.expand_path('../../..', __dir__))
  end
end

class Ticket
  class Article
    def self.exists?(*) = false
  end
end

# Stand-in for upstream's driver with the two methods the concern wraps.
class FakeGraphInbound
  MessageResult = Struct.new(:success, :after_action)

  attr_accessor :unread_ids, :fetch_results, :fetched

  def initialize(channel:, keep_on_server: true, graph: nil)
    @channel        = channel
    @keep_on_server = keep_on_server
    @graph          = graph
    @unread_ids     = []
    @fetch_results  = {}
    @fetched        = []
  end

  def messages_iterator(_keep_on_server, _options)
    [unread_ids.dup, unread_ids.size]
  end

  def fetch_single_message(message_id, _count, _count_all)
    fetched << message_id
    fetch_results.fetch(message_id) { MessageResult.new(true, nil) }
  end
end

require File.join(Rails.root, 'kc/app/models/concerns/kc/microsoft_graph_inbound_read_mail')
FakeGraphInbound.prepend(Kc::MicrosoftGraphInboundReadMail)

RSpec.describe Kc::MicrosoftGraphInboundReadMail do
  let(:channel)  { Struct.new(:id).new(42) }
  let(:graph)    { instance_double(Object) }
  let(:driver)   { FakeGraphInbound.new(channel:, graph:) }
  let(:imported) { Set.new(['<old@example.com>']) }
  let(:pages) do
    [{ value: [
      { id: 'r1', internetMessageId: '<old@example.com>' },
      { id: 'r2', internetMessageId: '<new@example.com>' },
    ], '@odata.nextLink': 'https://graph/next' },
     { value: [{ id: 'r3', internetMessageId: nil }] }]
  end
  let(:requests) { [] }

  before do
    Rails.cache.clear
    ENV.delete(described_class::WINDOW_ENV)
    responses = pages.dup
    allow(graph).to receive(:send) do |name, path|
      raise "unexpected #{name}" if name != :make_request

      requests << path
      responses.shift || { value: [] }
    end
    allow(Ticket::Article).to receive(:exists?) do |message_id_md5:|
      imported.any? { |mid| Digest::MD5.hexdigest(mid) == message_id_md5 }
    end
  end

  it 'adds read mail from the window that no article holds yet' do
    driver.unread_ids = ['u1']

    expect(driver.messages_iterator(true, {})).to eq([%w[u1 r2], 2])
  end

  it 'queries the folder for read mail inside the window, oldest first, following pages' do
    travel_now = Time.zone.parse('2026-11-14T20:00:00Z')
    allow(Time.zone).to receive(:now).and_return(travel_now)

    driver.messages_iterator(true, { folder_id: '' })

    first = CGI.unescape(requests.first)
    expect(first).to start_with('mailFolders/inbox/messages?')
    expect(first).to include('$filter=receivedDateTime ge 2026-11-11T20:00:00Z and isRead eq true')
    expect(first).to include('$orderby=receivedDateTime asc')
    expect(first).to include('$top=100')
    expect(requests.second).to eq('https://graph/next')
  end

  it 'uses the configured folder' do
    driver.messages_iterator(true, { folder_id: 'AAMk/abc=' })

    expect(requests.first).to start_with('mailFolders/AAMk%2Fabc%3D/messages?')
  end

  it 'does not list ids twice that upstream already listed as unread' do
    driver.unread_ids = ['r2']

    expect(driver.messages_iterator(true, {})).to eq([['r2'], 1])
  end

  it 'skips mail without a Message-ID' do
    expect(driver.messages_iterator(true, {}).first).not_to include('r3')
  end

  it 'never offers a processed message again, even when its article is gone later' do
    ids, count = driver.messages_iterator(true, {})
    ids.each.with_index(1) { |id, i| driver.fetch_single_message(id, i, count) }

    driver2 = FakeGraphInbound.new(channel:, graph:)
    pages.replace([{ value: [{ id: 'r2', internetMessageId: '<new@example.com>' }] }])
    allow(graph).to receive(:send).and_return(pages.first)

    expect(driver2.messages_iterator(true, {}).first).to eq([])
  end

  it 'offers a message again when upstream left it for a retry' do
    driver.fetch_results['r2'] = FakeGraphInbound::MessageResult.new(false, [:result_error, 'boom'])
    driver.fetch_single_message('r2', 1, 1)

    expect(driver.send(:kc_read_mail_remembered?, 'r2')).to be(false)
  end

  it 'remembers unread messages upstream processed' do
    driver.fetch_single_message('u1', 1, 1)

    expect(driver.send(:kc_read_mail_remembered?, 'u1')).to be(true)
  end

  it 'keeps upstream behaviour without keep_on_server' do
    driver.unread_ids = ['u1']

    expect(driver.messages_iterator(false, {})).to eq([['u1'], 1])
    expect(requests).to be_empty
  end

  it 'keeps upstream behaviour outside a fetch (check_configuration has no channel)' do
    no_channel = FakeGraphInbound.new(channel: nil, graph:)

    expect(no_channel.messages_iterator(true, {})).to eq([[], 0])
    expect(requests).to be_empty
  end

  it 'is switched off with a window of 0' do
    ENV[described_class::WINDOW_ENV] = '0'

    expect(driver.messages_iterator(true, {})).to eq([[], 0])
    expect(requests).to be_empty
  ensure
    ENV.delete(described_class::WINDOW_ENV)
  end

  it 'falls back to the default window on an invalid value and caps large ones' do
    ENV[described_class::WINDOW_ENV] = 'lots'
    expect(FakeGraphInbound.kc_read_mail_window_hours).to eq(72)
    ENV[described_class::WINDOW_ENV] = '9999'
    expect(FakeGraphInbound.kc_read_mail_window_hours).to eq(336)
  ensure
    ENV.delete(described_class::WINDOW_ENV)
  end

  it 'continues with the unread list when listing read mail fails' do
    allow(graph).to receive(:send).and_raise(StandardError, 'graph down')
    driver.unread_ids = ['u1']

    expect(driver.messages_iterator(true, {})).to eq([['u1'], 1])
  end

  it 'finds every upstream fingerprint in the current upstream driver' do
    source = File.read(Rails.root.join(described_class::UPSTREAM_FILE))

    expect(described_class::UPSTREAM_FINGERPRINT.reject { |n| source.include?(n) }).to be_empty
  end
end
