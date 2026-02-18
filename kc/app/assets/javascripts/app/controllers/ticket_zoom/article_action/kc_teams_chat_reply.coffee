# KC: Article action plugin for Teams Chat reply.
#
# Registers "teams_chat_message" as a reply option on tickets
# created from Teams Chat messages. Follows the same pattern as
# Zammad's Telegram and WhatsApp reply plugins.
#
# Three static methods:
#   @action       — adds "reply" button on Teams Chat articles
#   @perform      — sets compose area to teams_chat_message type
#   @articleTypes  — adds teams_chat_message to the article type dropdown

class KcTeamsChatReply

  @action: (actions, ticket, article, ui) ->
    return actions if !ticket.editable()
    return actions if ticket.currentView() is 'customer'
    return actions if article.type.name isnt 'teams_chat_message'

    actions.push {
      name: __('reply')
      type: 'teamsChatReply'
      icon: 'reply'
      href: '#'
    }
    actions

  @perform: (articleContainer, type, ticket, article, ui) ->
    return true if type isnt 'teamsChatReply'

    ui.scrollToCompose()

    articleType = App.TicketArticleType.findByAttribute('name', 'teams_chat_message')

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
    return articleTypes if !ticket || !ticket.create_article_type_id
    return articleTypes if ticket.currentView() is 'customer'

    articleTypeCreate = App.TicketArticleType.find(ticket.create_article_type_id)
    return articleTypes if !articleTypeCreate
    return articleTypes if articleTypeCreate.name isnt 'teams_chat_message'

    articleTypes.push {
      name:       'teams_chat_message'
      icon:       'message'
      attributes: []
      internal:   false
      features:   ['attachment']
    }
    articleTypes

App.Config.set('300-KcTeamsChatReply', KcTeamsChatReply, 'TicketZoomArticleAction')
