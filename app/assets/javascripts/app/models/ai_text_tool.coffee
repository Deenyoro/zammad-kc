class App.AITextTool extends App.Model
  @configure 'AITextTool', 'name', 'instruction', 'group_ids', 'note', 'active'
  @extend Spine.Model.Ajax
  @url = @apiPath + '/ai_text_tools'
  @configure_attributes = [
    { name: 'name',        display: __('Name'),                tag: 'input', type: 'text', translate: true, limit: 100, null: false },
    { name: 'instruction', display: __('Custom instructions'), tag: 'richtext', limit: 2000, null: false, plugins: [
      {
        controller: 'WidgetPlaceholder'
        params:
          objects: [
            {
              prefix: 'ticket'
              object: 'Ticket'
              display: __('Ticket')
            },
            {
              prefix: 'user'
              object: 'User'
              display: __('Current User')
            },
          ]
      }
    ], note: __('To select placeholders from a list, just enter "::".'), help: __('Provide specific and unambiguous instructions for the LLM to process a given text which will be part of the system prompt.')},
    { name: 'fixed_instructions', display: __('Default instructions'), tag: 'textarea', null: true, disabled: true, help: __('We add fixed instructions about output format to the system prompt.'), collapsible: true, collapsed: true },
    { name: 'group_ids',          display: __('Groups'),               tag: 'column_select', relation: 'Group', null: true, unsortable: true, display_full_name: true },
    { name: 'note',               display: __('Note'),                 tag: 'textarea',      limit:   250,      null: true },
    { name: 'active',             display: __('Active'),               tag: 'active',        default: true },
  ]
  @configure_delete = true
  @configure_clone = true
  @configure_overview = [
    'name',
    'group_ids',
    'note',
  ]
  @description = __('''
    Write Assistant Tools simplify the process of refining an article text before saving or sending. When enabled, these tools are directly accessible within the article editor. You can even create custom tools to meet specific needs, e.g. using branch or company specific wording.
''')