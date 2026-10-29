# KC: run in a Zammad test environment after copying kc/ into the app tree
# (kc/script/apply-overlay.sh, then cp -r kc/spec/. spec/):
#   bundle exec rspec spec/requests/kc/scheduled_articles_spec.rb

require 'rails_helper'

RSpec.describe 'KC scheduled articles', type: :request do
  let(:group)  { create(:group) }
  let(:agent)  { create(:agent, groups: [group]) }
  let(:ticket) { create(:ticket, group: group) }
  let(:url)    { "/api/v1/kc/tickets/#{ticket.id}/scheduled_articles" }

  def add_file(form_id, filename, content_type: 'text/plain', data: "content of #{filename}")
    UploadCache.new(form_id).add(
      data:          data,
      filename:      filename,
      preferences:   { 'Content-Type' => content_type },
      created_by_id: agent.id,
    )
  end

  def schedule(form_id, attachments: nil)
    params = {
      article_data: { body: 'later', type: 'note', internal: true, content_type: 'text/plain', form_id: form_id },
      scheduled_at: 1.hour.from_now.iso8601,
    }
    params[:attachments] = attachments if !attachments.nil?

    post url, params: params, as: :json
    expect(response).to have_http_status(:created)

    Kc::ScheduledArticle.find(json_response['id'])
  end

  def send_now(scheduled)
    UserInfo.with_user_id(agent.id) { Kc::ExecuteScheduledArticle.new(scheduled.reload).execute! }
  end

  def stored_files(scheduled)
    Store.list(object: 'Kc::ScheduledArticle', o_id: scheduled.id)
  end

  before { authenticated_as(agent) }

  context 'with a legacy UI reply (numeric form id, no file list)' do
    let(:form_id) { 123_456_789 }

    it 'copies the form files and sends them', :aggregate_failures do
      add_file(form_id, 'legacy.txt')

      scheduled = schedule(form_id)

      expect(scheduled.article_data).not_to have_key('form_id')
      expect(stored_files(scheduled).map(&:filename)).to eq(['legacy.txt'])

      article = send_now(scheduled)

      expect(article.attachments.map(&:filename)).to eq(['legacy.txt'])
      expect(article.attachments.first.content).to eq('content of legacy.txt')
      expect(scheduled.reload.status).to eq('sent')
      expect(stored_files(scheduled)).to be_empty
    end

    it 'still sends replies scheduled before stored copies existed from the form cache', :aggregate_failures do
      add_file(form_id, 'old.txt')
      scheduled = Kc::ScheduledArticle.create!(
        ticket_id:     ticket.id,
        article_data:  { 'body' => 'later', 'type' => 'note', 'internal' => true, 'form_id' => form_id.to_s },
        scheduled_at:  1.minute.from_now,
        status:        'pending',
        created_by_id: agent.id,
        updated_by_id: agent.id,
      )

      article = send_now(scheduled)

      expect(article.attachments.map(&:filename)).to eq(['old.txt'])
      expect(UploadCache.new(form_id).attachments(created_by_id: nil)).to be_empty
    end
  end

  context 'with a new UI reply (UUID form id, selected files)' do
    let(:form_id) { SecureRandom.uuid }

    it 'sends only the selected files, not files added to the form later', :aggregate_failures do
      add_file(form_id, 'selected.pdf', content_type: 'application/pdf')
      add_file(form_id, 'removed-from-reply.txt')

      scheduled = schedule(form_id, attachments: [{ name: 'selected.pdf', type: 'application/pdf' }])

      # The agent goes on in the same tab (same form id) and attaches a file
      # to a different reply.
      add_file(form_id, 'other-reply.txt')

      article = send_now(scheduled)

      expect(article.attachments.map(&:filename)).to eq(['selected.pdf'])
      # The form's own cache is left alone (it belongs to the open tab).
      expect(UploadCache.new(form_id).attachments(created_by_id: agent.id).map(&:filename)).to include('other-reply.txt')
    end

    it 'keeps the files when the form cache is purged before sending', :aggregate_failures do
      add_file(form_id, 'kept.txt')
      scheduled = schedule(form_id, attachments: [{ name: 'kept.txt', type: 'text/plain' }])

      UserInfo.with_user_id(nil) { UploadCache.new(form_id).destroy }

      expect(send_now(scheduled).attachments.map(&:filename)).to eq(['kept.txt'])
    end

    it 'sends no files when none were selected' do
      add_file(form_id, 'not-selected.txt')
      scheduled = schedule(form_id, attachments: [])

      expect(send_now(scheduled).attachments).to be_empty
    end
  end

  context 'when cancelling' do
    let(:form_id) { SecureRandom.uuid }

    it 'removes the stored files', :aggregate_failures do
      add_file(form_id, 'cancel.txt')
      scheduled = schedule(form_id, attachments: [{ name: 'cancel.txt', type: 'text/plain' }])
      expect(stored_files(scheduled).count).to eq(1)

      delete "#{url}/#{scheduled.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(scheduled.reload.status).to eq('cancelled')
      expect(stored_files(scheduled)).to be_empty
    end

    it 'copies the files back into the compose form on "Edit"', :aggregate_failures do
      add_file(form_id, 'edit.txt')
      scheduled = schedule(form_id, attachments: [{ name: 'edit.txt', type: 'text/plain' }])
      edit_form_id = SecureRandom.uuid

      delete "#{url}/#{scheduled.id}", params: { restore_form_id: edit_form_id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response['attachments'].pluck('filename')).to eq(['edit.txt'])
      restored = UploadCache.new(edit_form_id).attachments(created_by_id: agent.id)
      expect(restored.map(&:filename)).to eq(['edit.txt'])
      expect(json_response['attachments'].first['id']).to eq(restored.first.id)
      expect(stored_files(scheduled)).to be_empty
    end

    it 'does not cancel when the reply was already sent', :aggregate_failures do
      scheduled = schedule(form_id, attachments: [])
      scheduled.update!(status: 'sent')

      delete "#{url}/#{scheduled.id}", params: { restore_form_id: SecureRandom.uuid }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(scheduled.reload.status).to eq('sent')
    end
  end
end
