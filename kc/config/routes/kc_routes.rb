# KC custom API routes.
# Auto-loaded by Zammad's config/routes.rb which globs config/routes/*.rb.

Zammad::Application.routes.draw do
  scope '/api/v1/kc', as: :kc do
    # Time entry CRUD (ticket sidebar)
    get    'tickets/:ticket_id/time_entries',     to: 'kc/time_management#ticket_entries'
    post   'tickets/:ticket_id/time_entries',     to: 'kc/time_management#create_entry'
    delete 'tickets/:ticket_id/time_entries/:id', to: 'kc/time_management#destroy_entry'

    # Reporting (admin)
    get 'time_management/by_user/:year/:month',         to: 'kc/time_management#by_user'
    get 'time_management/by_organization/:year/:month',  to: 'kc/time_management#by_organization'

    # Teams Chat channel admin
    get    'teams_chat_channels',              to: 'kc/teams_chat_channels#index'
    post   'teams_chat_channels/authorize',    to: 'kc/teams_chat_channels#authorize_oauth'
    match  'teams_chat_channels/callback',     to: 'kc/teams_chat_channels#callback', via: [:get, :post]
    put    'teams_chat_channels/:id',          to: 'kc/teams_chat_channels#update'
    post   'teams_chat_channels/:id/enable',   to: 'kc/teams_chat_channels#enable'
    post   'teams_chat_channels/:id/disable',  to: 'kc/teams_chat_channels#disable'
    post   'teams_chat_channels/:id/sync_directory', to: 'kc/teams_chat_channels#sync_directory'
    delete 'teams_chat_channels/:id',          to: 'kc/teams_chat_channels#destroy'

    # Teams Chat webhook (public — no auth, validated by clientState)
    post 'teams_chat_webhook', to: 'kc/teams_chat_webhook#webhook'

    # RingCentral SMS channel admin
    get    'ringcentral_sms_channels',                to: 'kc/ringcentral_sms_channels#index'
    post   'ringcentral_sms_channels/authorize',      to: 'kc/ringcentral_sms_channels#authorize_oauth'
    match  'ringcentral_sms_channels/callback',       to: 'kc/ringcentral_sms_channels#callback', via: [:get, :post]
    get    'ringcentral_sms_channels/pending_setup',  to: 'kc/ringcentral_sms_channels#pending_setup'
    post   'ringcentral_sms_channels/complete_setup', to: 'kc/ringcentral_sms_channels#complete_setup'
    put    'ringcentral_sms_channels/:id',            to: 'kc/ringcentral_sms_channels#update'
    post   'ringcentral_sms_channels/:id/enable',     to: 'kc/ringcentral_sms_channels#enable'
    post   'ringcentral_sms_channels/:id/disable',    to: 'kc/ringcentral_sms_channels#disable'
    delete 'ringcentral_sms_channels/:id',            to: 'kc/ringcentral_sms_channels#destroy'

    # RingCentral SMS webhook (public — no auth, validated by subscription lookup)
    post 'ringcentral_sms_webhook', to: 'kc/ringcentral_sms_webhook#webhook'

    # New conversation initiation (agent-facing)
    post 'conversations/sms',          to: 'kc/new_conversations#sms'
    post 'conversations/teams',        to: 'kc/new_conversations#teams'
    get  'conversations/sms_users',    to: 'kc/new_conversations#sms_users'
    get  'conversations/teams_contacts', to: 'kc/new_conversations#teams_contacts'
  end
end
