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
  end
end
