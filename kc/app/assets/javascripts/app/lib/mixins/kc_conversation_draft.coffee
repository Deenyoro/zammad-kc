# KC: Taskbar draft behaviour shared by the "new conversation" screens
# (RingCentral SMS, FreePBX SMS, Teams chat).
#
# Mirrors what App.TicketCreate does for the ticket create screen: every
# screen is a taskbar task of its own (key "<prefix>-<id>"), shown with the
# pen icon, whose form state is stored in the task (task.state) and restored
# when the task is started again - after switching tabs, or after a reload,
# when App.TaskManager re-creates the controller from the stored callback.
#
# A controller including this mixin provides:
#
#   draftRoute:            route of the screen without the id, e.g. 'kc/new_rcsms'
#   draftLabel:            untranslated tab label, e.g. __('SMS')
#   draftForm:             selector of the form the state is collected from
#   draftCollect():        current form values as a flat object
#   draftApply(state):     writes stored values back into the rendered form
#   draftDetail(state):    optional text shown behind the label ("SMS: +1555...")
#   draftHasContent(state): whether the values hold anything typed by the agent
#
# and calls draftRestore() after rendering, draftSave() after changing form
# values from code, and draftClose() once the conversation has been created.
App.KcConversationDraft =
  draftStored: ->
    task = App.TaskManager.get(@taskKey)
    return {} if !task || !task.state
    task.state

  draftCurrent: ->
    return @draftStored() if !@el || !@el.find(@draftForm).get(0)
    @draftCollect()

  meta: ->
    label  = App.i18n.translateInline(@draftLabel)
    detail = @draftDetail?(@draftCurrent())
    text   = if detail then "#{label}: #{detail}" else label

    url:       @url()
    head:      text
    title:     text
    id:        @id
    iconClass: 'pen'

  url: ->
    "##{@draftRoute}/id/#{@id}"

  show: ->
    @navupdate(@url(), type: 'menu')
    @draftAutosaveStart()

  hide: ->
    # store what was typed right before leaving the tab
    @draftSave() if @draftSavePending
    @draftAutosaveStop()

  # Asked by the taskbar before closing the tab and by the automatic cleanup
  # of old tabs - a draft with typed content is neither closed silently nor
  # cleaned up.
  changed: ->
    @draftHasContent(@draftCurrent())

  draftRestore: ->
    state = @draftStored()
    @draftLast = _.clone(state)
    return if _.isEmpty(state)

    # applying the values must not store a half restored form
    @draftRestoring = true
    try
      @draftApply(state)
    finally
      @draftRestoring = false

  draftAutosaveStart: ->
    @draftAutosaveStop()
    @el.on('change.kcDraft input.kcDraft keyup.kcDraft paste.kcDraft', @draftForm, =>
      @draftSavePending = true
      @delay((=> @draftSave()), 250, 'kc-conversation-draft-save')
    )

  draftAutosaveStop: ->
    @clearDelay('kc-conversation-draft-save')
    @el.off('.kcDraft')

  draftSave: ->
    @draftSavePending = false
    return if @draftClosed || @draftRestoring
    return if !App.TaskManager.get(@taskKey)
    return if !@el || !@el.find(@draftForm).get(0)

    data = @draftCollect()
    return if _.isEqual(@draftLast, data)

    detailBefore = @draftDetail?(@draftLast || {})
    @draftLast   = _.clone(data)
    App.TaskManager.update(@taskKey, { state: data })

    # a state-only update does not re-render the tab, the title might change
    App.TaskManager.touch(@taskKey) if @draftDetail?(data) isnt detailBefore

  # Closes the tab of a sent conversation, like the ticket create screen does
  # after creating the ticket.
  draftClose: ->
    @draftClosed = true
    @draftAutosaveStop()
    App.TaskManager.remove(@taskKey)

# KC: Route handler for a draft screen: a route without id starts a new draft
# with a random id (one tab per draft, several drafts at once, like
# "#ticket/create"), a route with id opens (or re-opens) that draft's task.
App.KcConversationDraftRouter = (route, keyPrefix, controller) ->
  class KcConversationDraftRouter extends App.ControllerPermanent
    @requiredPermission: ['ticket.agent']

    constructor: (params) ->
      super

      if !params.id
        id = Math.floor(Math.random() * 99999)
        @navigate "##{route}/id/#{id}", { hideCurrentLocationFromHistory: true }
        return

      @authenticateCheckRedirect()

      App.TaskManager.execute(
        key:        "#{keyPrefix}-#{params.id}"
        controller: controller
        params:
          id: params.id
        show:       true
      )
