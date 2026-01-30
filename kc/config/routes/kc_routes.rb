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
    get    'teams_chat_channels/callback',     to: 'kc/teams_chat_channels#callback'
    put    'teams_chat_channels/:id',          to: 'kc/teams_chat_channels#update'
    post   'teams_chat_channels/:id/enable',   to: 'kc/teams_chat_channels#enable'
    post   'teams_chat_channels/:id/disable',  to: 'kc/teams_chat_channels#disable'
    delete 'teams_chat_channels/:id',          to: 'kc/teams_chat_channels#destroy'

    # Teams Chat webhook (public — no auth, validated by clientState)
    post 'teams_chat_webhook', to: 'kc/teams_chat_webhook#webhook'
  end
end
