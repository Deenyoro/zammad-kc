# default model also in lib/ai/provider/mistral.rb
App.Config.set('mistral', {
  key:    'mistral'
  label:  __('Mistral')
  prio:   6000
  fields: ['token', 'model']
  active: true
  default_model: 'mistral-medium-latest'
}, 'AIProviders')
