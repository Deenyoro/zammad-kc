# Methods for initializing and using text tools in the richtext editor context.

App.TextTools =
  textToolsInit: (el, disabled = false) ->
    return if not App.User.current()?.permission('ticket.agent')
    return if not App.Config.get('ai_provider')
    return if not App.Config.get('ai_assistance_text_tools')

    ce = el.find('[contenteditable]').data().plugin_ce

    ce.onSelection((selection) ->
      el.find('.js-textToolsDropdown').remove()

      return if not App.Config.get('ai_provider')
      return if not App.Config.get('ai_assistance_text_tools')
      return if not selection.content

      dropdown = el
        .after( $( App.view('generic/text_tools_dropdown')(disabled: false) ) )
        .next()

      if range = selection.ranges[0]
        dropdown.offset(range.getBoundingClientRect())

      closeDropdown = ->
        dropdown
          .removeClass('open')
          .remove()

      dropdown.off('click.text-tools-actions', '.js-action').on('click.text-tools-actions', '.js-action', (e) ->
        e.preventDefault()

        action = $(e.target).data('type')

        closeDropdown()

        new App.TextToolsModal(
          container: el.closest('.content')
          service: action
          selectedText: selection.content
          approve: (result) -> ce.replaceSelection(selection.ranges, result)
        )
      )

      dropdown.addClass('open')

      dropdownMenu = dropdown.find('.dropdown-menu')

      if not dropdownMenu.visible()
        offsetTop = 10
        header = el.closest('.content').find('.scrollPageHeader')
        if header.length and header.visible()
          offsetTop += header.height()
        dropdownMenu.ScrollTo({ offsetTop })

      setTimeout(->
        $(window).off('click.dropdown-menu, keyup.dropdown-menu').on('click.dropdown-menu, keyup.dropdown-menu', (e) ->
          return if e.type is 'keyup' and e.key.startsWith('Shift')
          closeDropdown()
          $(window).off('click.dropdown-menu, keyup.dropdown-menu')
        )

        el.one('click.dropdown-menu', (e) ->
          closeDropdown()
        )
      , 100)
    )
