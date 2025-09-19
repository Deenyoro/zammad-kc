# coffeelint: disable=camel_case_classes
class App.UiElement.auth_provider
  @render: (attributeConfig) ->
    attribute = $.extend(true, {}, attributeConfig)

    for key, value of App.Config.get('auth_provider_all')
      continue if value.config isnt attribute.provider
      attribute.value = "#{App.Config.get('http_type')}://#{App.Config.get('fqdn')}#{value.url}/callback"
      break

    content = $( App.view('generic/auth_provider')( attribute: attribute ) )

    content.find('.js-select').off('click.selectAll').on('click.selectAll', (e) ->
      e.currentTarget.focus()
      e.currentTarget.select()
    )

    content.find('.js-copy').off('click.copyToClipboard').on('click.copyToClipboard', (e) ->
      e.preventDefault()

      button = $(e.target).parents('[role="button"]')
      fieldId = button.data('targetField')
      value = content.find("input[id='#{jQuery.escapeSelector(fieldId)}']").val()

      clipboard.writeText(value)

      tooltipCopied = content.find(e.target).tooltip(
        trigger:   'manual'
        placement: 'bottom'
        title: ->
          App.i18n.translateContent('Copied!')
      )
      tooltipCopied.tooltip('show')

      App.Delay.set(->
        tooltipCopied.tooltip('hide')
      , 1500)
    )

    content
