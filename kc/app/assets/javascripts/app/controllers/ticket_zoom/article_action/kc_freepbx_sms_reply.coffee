# KC: Article action plugin for FreePBX SMS reply.
#
# Registers "freepbx_sms_message" as a reply option on tickets created
# from FreePBX text messages. Mirrors kc_ringcentral_sms_reply.coffee.

class KcFreepbxSmsReply

  @action: (actions, ticket, article, ui) ->
    return actions if !ticket.editable()
    return actions if ticket.currentView() is 'customer'
    return actions if article.type?.name isnt 'freepbx_sms_message'

    actions.push {
      name: __('reply')
      type: 'freepbxSmsReply'
      icon: 'reply'
      href: '#'
    }
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    return true if type isnt 'freepbxSmsReply'

    ui.scrollToCompose()

    articleType = App.TicketArticleType.findByAttribute('name', 'freepbx_sms_message')

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

    isSmsTicket = false
    if ticket.create_article_type_id
      articleTypeCreate = App.TicketArticleType.find(ticket.create_article_type_id)
      isSmsTicket = true if articleTypeCreate && articleTypeCreate.name is 'freepbx_sms_message'

    if !isSmsTicket && ticket.preferences && ticket.preferences.freepbx_sms
      isSmsTicket = true

    return articleTypes if !isSmsTicket

    articleTypes.push {
      name:       'freepbx_sms_message'
      icon:       'message'
      attributes: []
      internal:   false
      features:   ['attachment']
    }
    articleTypes

App.Config.set('311-KcFreepbxSmsReply', KcFreepbxSmsReply, 'TicketZoomArticleAction')
