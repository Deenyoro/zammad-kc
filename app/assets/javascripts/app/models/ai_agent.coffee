class App.AIAgent extends App.Model
  @configure 'AIAgent', 'name', 'definition', 'action_definition', 'note', 'active'
  @extend Spine.Model.Ajax
  @url: @apiPath + '/ai_agents'
  @configure_attributes = [
    { name: 'name',                display: __('Name'),                      tag: 'input',    type: 'text', limit: 250, null: false },
    { name: 'type',                display: __('Type'),                      tag: 'select',   options: { TicketGroupDispatcher: __('Ticket Group Dispatcher') } }, # TODO
    { name: 'triggers',            display: __('Used in triggers'),                           readonly: 1 },
    { name: 'jobs',                display: __('Used in schedulers'),                         readonly: 1 },
    { name: 'note',                display: __('Note'),                      tag: 'textarea', null: true, note: '', limit: 250 },
    { name: 'active',              display: __('Active'),                    tag: 'active',   default: true },
    { name: 'updated_at',          display: __('Updated'),                   tag: 'datetime', readonly: 1 },
  ]
  @configure_delete = true
  @configure_clone = true
  @configure_overview = [
    'name',
    'type',
    'triggers',
    'jobs',
    'note',
  ]

  @description = __('''
AI agents enable streamlined processing powered by AI-driven insights. You can execute AI agents via triggers or schedulers.
''')

  @badges = [
    {
      display: __('Unused'),
      title: __('This AI agent is not used in any triggers or schedulers and will not run.'),
      active: (object) ->
        _.isEmpty(object.references) and object.active
      attribute: 'name'
      class: 'warning'
    }
  ]
