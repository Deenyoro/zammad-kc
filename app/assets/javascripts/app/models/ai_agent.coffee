class App.AIAgent extends App.Model
  @configure 'AIAgent', 'name', 'definition', 'action_definition', 'note', 'active'
  @extend Spine.Model.Ajax
  # @url: @apiPath + '/ai_agents' API path not available
  @configure_attributes = [
    { name: 'name',                display: __('Name'),                      tag: 'input',       type: 'text', limit: 250, null: false },
    { name: 'note',                display: __('Note'),                      tag: 'textarea',    null: true, note: '', limit: 250 },
    { name: 'active',              display: __('Active'),                    tag: 'active',      default: true },
    { name: 'updated_at',          display: __('Updated'),                   tag: 'datetime',    readonly: 1 },
  ]
  @configure_delete = true
  @configure_clone = true
  @configure_overview = [
    'name',
  ]

  @description = __('''
AI Agents allow to enhance triggers with AI insights AI.
''')
