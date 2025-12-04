# default model also in lib/ai/provider/mistral.rb
App.Config.set('mistral', {
  key:    'mistral'
  label:  __('Mistral AI')
  prio:   6000
  fields: ['token', 'model']
  required: ['token']
  default_model: 'mistral-medium-latest'
}, 'AIProviders')
