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
    return articleTypes if ticket.currentView() is 'customer'
    return articleTypes if !ticket || !ticket.create_article_type_id

    articleTypeCreate = App.TicketArticleType.find(ticket.create_article_type_id)
    return articleTypes if !articleTypeCreate
    return articleTypes if articleTypeCreate.name isnt 'ringcentral_sms_message'

    articleTypes.push {
      name:       'ringcentral_sms_message'
      icon:       'message'
      attributes: []
      internal:   false
      features:   ['attachment']
    }
    articleTypes

App.Config.set('310-KcRingcentralSmsReply', KcRingcentralSmsReply, 'TicketZoomArticleAction')
