class App.Channel extends App.Model
  @configure 'Channel', 'adapter', 'area', 'options', 'group_id', 'active'
  @extend Spine.Model.Ajax
  @url: @apiPath + '/channels'

  displayName: ->
    name = ''
    if @options
      if @options.inbound and @options.inbound.options?.user
        if @options.inbound.options.host
          name += "#{@options.inbound.options.user}@#{@options.inbound.options.host} (#{@options.inbound.adapter})"
        else
          name += "#{@options.inbound.options.user} (#{@options.inbound.adapter})"
      else
        name += "(#{@options.inbound.adapter})"
      if @options.outbound
        if name != ''
          name += ' / '
        if @options.outbound.options?.host
          name += "#{@options.outbound.options.host} (#{@options.outbound.adapter})"
        else
          name += "(#{@options.outbound.adapter})"
    if name == ''
      name = '-'
    name
