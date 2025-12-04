# default model also in lib/ai/provider/ollama.rb
App.Config.set('ollama', {
  key:    'ollama'
  label:  __('Ollama')
  prio:   3000
  url_placeholder: 'http://localhost:11434'
  fields: ['url', 'model']
  required: ['url']
  default_model: 'llama3.2'
}, 'AIProviders')
