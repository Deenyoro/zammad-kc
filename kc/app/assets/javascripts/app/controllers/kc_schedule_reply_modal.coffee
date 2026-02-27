# KC: Modal for selecting the datetime to schedule a reply.
#
# Extends App.ControllerModal with a single datetime field.
# On submit, calls @submitCallback with the selected datetime.
#
# This modal uses container (rendered inside ticket content area) which
# is required for formParams() and event delegation to work. However,
# Bootstrap's hidden.bs.modal event never fires for container modals,
# so we override close() to force cleanup after the animation.
class App.KcScheduleReplyModal extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: __('Schedule')
  buttonClass: 'btn--primary'
  head: __('Schedule Reply')
  small: true

  events:
    'submit form':                        'submit'
    'click .js-submit:not(.is-disabled)': 'submit'
    'click .js-cancel':                   'cancel'
    'click .js-close':                    'cancel'

  content: ->
    configure_attributes = [
      {
        name:        'scheduled_at'
        display:     __('Send at')
        tag:         'datetime'
        null:        false
        future:      true
        placeholder: __('Select date and time')
      }
    ]

    @form = new App.ControllerForm(
      model:     { configure_attributes: configure_attributes }
      autofocus: true
    )

    @form.el

  onSubmit: (e) =>
    e.preventDefault()
    @formDisable(e)

    params = @formParams()

    errors = @form.validate(params)
    if !_.isEmpty(errors)
      @formEnable(e)
      @formValidate(form: @form.el, errors: errors)
      return false

    if !params.scheduled_at
      @formEnable(e)
      @formValidate(form: @form.el, errors: { scheduled_at: __('is required') })
      return false

    # Validate the datetime is in the future
    scheduledDate = new Date(params.scheduled_at)
    if scheduledDate <= new Date()
      @formEnable(e)
      @formValidate(form: @form.el, errors: { scheduled_at: __('must be in the future') })
      return false

    # Fire callback before close — the AJAX call is async (returns immediately),
    # so the modal animation completes well before the server responds and
    # taskReset() runs.
    @submitCallback(params) if @submitCallback
    @close()

  # Override close to force cleanup. Bootstrap's hidden.bs.modal never fires
  # for container modals, so the base class's localOnClosed (which calls
  # modal('remove')) never runs. We manually remove the modal and backdrop
  # after the 300ms fade-out animation completes.
  close: (e) =>
    if e
      e.preventDefault()
    @initalFormParamsIgnore = true
    @el.modal('hide')
    @delay(=>
      @onClose?()
      @el.remove()
      @container?.find('.modal-backdrop').remove()
      $('body').removeClass('modal-open')
    , 400)
