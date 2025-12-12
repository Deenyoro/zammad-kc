# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Service::AI::Ticket::PreProcessArticleContent do
  let(:ocr_active) { true }
  let(:ticket)     { create(:ticket) }

  let(:articles) do
    create_list(
      :ticket_article,
      3,
      ticket:       ticket,
      content_type: 'text/html',
    ) do |article, index|
      cid = "#{SecureRandom.uuid}@zammad.example.com"

      # Create inline image for each article.
      create(
        :store,
        :image,
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        "inline:#{cid}", # store the cid in the data, so it's different for each attachment
        preferences: {
          'Content-Type' => 'image/png; name="filename.png"',
          'Mime-Type'    => 'image/png',
          'Content-ID'   => "<#{cid}>",
          # FIXME: Check if we can go back to relying on Content-Disposition for inline detection.
          # 'Content-Disposition' => 'inline; filename="filename.png"',
        }
      )

      article.body = "<img src=\"cid:#{cid}\"> some text"

      # Create also an image attachment that is not inline.
      create(
        :store,
        :image,
        object:      'Ticket::Article',
        o_id:        article.id,
        data:        "attachment:#{cid}", # store the cid in the data, so it's different for each attachment
        preferences: {
          'Content-Type' => 'image/png; name="filename.png"',
          'Mime-Type'    => 'image/png',
          # FIXME: Check if we can go back to relying on Content-Disposition for inline detection.
          # 'Content-Disposition' => 'attachment; filename="filename.png"',
        }
      )

      # Alternate sender type between customer and agent.
      if index.odd?
        article.sender = Ticket::Article::Sender.lookup(name: 'Agent')
      end

      article.save!
    end
  end

  before do
    attachments = articles.inject([]) do |acc, article|
      acc + article.attachments
    end

    setup_ai_provider('zammad_ai', ocr_active: ocr_active)

    # Mock image recognition, but return different text for each attachment.
    attachments.each_with_index do |attachment, index|
      allow_any_instance_of(AI::Provider::ZammadAI)
        .to receive(:ask)
        .with(hash_including(prompt_image: attachment))
        .and_return("image description #{index + 1}")
    end
  end

  describe '#execute' do
    subject(:service) { described_class.new(articles: ticket.articles.without_system_notifications) }

    it 'replaces inline images and image attachments with recognized texts' do
      expect(service.execute).to contain_exactly(
        include(
          sender_type: ticket.articles.first.sender.name,
          sender_name: ticket.articles.first.author.fullname,
          created_at:  ticket.articles.first.created_at,
          visibility:  'public',
          text:        "[OCR_TEXT_START]\nimage description 1\n[OCR_TEXT_END] some text",
          attachments: [
            { text: 'image description 2', type: 'image/png' },
          ],
        ),
        include(
          sender_type: ticket.articles.second.sender.name,
          sender_name: ticket.articles.second.author.fullname,
          created_at:  ticket.articles.second.created_at,
          visibility:  'public',
          text:        "[OCR_TEXT_START]\nimage description 3\n[OCR_TEXT_END] some text",
          attachments: [
            { text: 'image description 4', type: 'image/png' },
          ],
        ),
        include(
          sender_type: ticket.articles.third.sender.name,
          sender_name: ticket.articles.third.author.fullname,
          created_at:  ticket.articles.third.created_at,
          visibility:  'public',
          text:        "[OCR_TEXT_START]\nimage description 5\n[OCR_TEXT_END] some text",
          attachments: [
            { text: 'image description 6', type: 'image/png' },
          ],
        )
      )
    end

    context 'when OCR is deactivated' do
      let(:ocr_active) { false }

      it 'strips inline images and does not return image attachments' do
        expect(service.execute).to contain_exactly(
          include(
            sender_type: ticket.articles.first.sender.name,
            sender_name: ticket.articles.first.author.fullname,
            created_at:  ticket.articles.first.created_at,
            visibility:  'public',
            text:        'some text',
          ),
          include(
            sender_type: ticket.articles.second.sender.name,
            sender_name: ticket.articles.second.author.fullname,
            created_at:  ticket.articles.second.created_at,
            visibility:  'public',
            text:        'some text',
          ),
          include(
            sender_type: ticket.articles.third.sender.name,
            sender_name: ticket.articles.third.author.fullname,
            created_at:  ticket.articles.third.created_at,
            visibility:  'public',
            text:        'some text',
          )
        )
      end
    end
  end
end
