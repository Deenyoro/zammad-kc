# KC custom API routes.
# Auto-loaded by Zammad's config/routes.rb which globs config/routes/*.rb.

Zammad::Application.routes.draw do
  scope '/api/v1/kc', as: :kc do
    # Add custom KC routes here. Examples:
    #   resources :widgets, controller: 'kc/widgets', only: %i[index show create update destroy]
    #   get  'health',  to: 'kc/health#index'
    #   post 'webhook', to: 'kc/webhooks#create'
  end
end
