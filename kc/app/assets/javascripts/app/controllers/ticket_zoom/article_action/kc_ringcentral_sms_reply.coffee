# KC: Article action plugin for RingCentral SMS reply.
#
# Registers "ringcentral_sms_message" as a reply option on tickets
# created from RingCentral SMS messages. Follows the same pattern as
# Zammad's Telegram and WhatsApp reply plugins.
#
# Three static methods:
#   @action       — adds "reply" button on RingCentral SMS articles
#   @perform      — sets compose area to ringcentral_sms_message type
#   @articleTypes  — adds ringcentral_sms_message to the article type dropdown

class KcRingcentralSmsReply

  @action: (actions, ticket, article, ui) ->
    return actions if !ticket.editable()
    return actions if ticket.currentView() is 'customer'
    return actions if article.type.name isnt 'ringcentral_sms_message'

    actions.push {
      name: __('reply')
      type: 'ringcentralSmsReply'
      icon: 'reply'
      href: '#'
    }
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    return true if type isnt 'ringcentralSmsReply'

    ui.scrollToCompose()

    articleType = App.TicketArticleType.findByAttribute('name', 'ringcentral_sms_message')

    articleNew = {
      to:          ''
      cc:          ''
      body:        ''
      in_reply_to: ''
    }

    if articleType
      App.Event.trigger('ui::ticket::setArticleType', {
        ticket:  ticket
        type:    articleType
        article: articleNew
      })
    true

  @articleTypes: (articleTypes, ticket, ui) ->
    return articleTypes if !ticket
    return articleTypes if ticket.currentView() is 'customer'

    # Check if this is an SMS ticket via create_article_type_id or ticket preferences
    isSmsTicket = false
    if ticket.create_article_type_id
      articleTypeCreate = App.TicketArticleType.find(ticket.create_article_type_id)
      isSmsTicket = true if articleTypeCreate && articleTypeCreate.name is 'ringcentral_sms_message'

    # Fallback: check ticket preferences (covers skip-send tickets where
    # create_article_type_id may not match on older tickets)
    if !isSmsTicket && ticket.preferences && ticket.preferences.ringcentral_sms
      isSmsTicket = true

    return articleTypes if !isSmsTicket

    articleTypes.push {
      name:       'ringcentral_sms_message'
      icon:       'message'
      attributes: []
      internal:   false
      features:   ['attachment']
    }
    articleTypes

App.Config.set('310-KcRingcentralSmsReply', KcRingcentralSmsReply, 'TicketZoomArticleAction')
