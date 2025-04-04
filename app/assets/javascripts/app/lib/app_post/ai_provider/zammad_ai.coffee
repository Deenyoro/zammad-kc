App.Config.set('zammad_ai', {
  key:    'zammad_ai'
  label:  __('Zammad AI')
  order:  1000
  fields: ['token']
  active: -> App.Config.get('system_online_service') || App.Config.get('developer_mode')
}, 'AIProviders')
