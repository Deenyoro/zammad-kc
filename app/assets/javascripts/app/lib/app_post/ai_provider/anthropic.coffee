# default model also in lib/ai/provider/anthropic.rb
App.Config.set('anthropic', {
  key:    'anthropic'
  label:  __('Anthropic')
  prio:   4000
  fields: ['token', 'model']
  active: true
  default_model: 'claude-3-7-sonnet-latest'
}, 'AIProviders')
