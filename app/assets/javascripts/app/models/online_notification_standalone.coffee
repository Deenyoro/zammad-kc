class App.OnlineNotificationStandalone extends App.Model
  @configure 'OnlineNotificationStandalone', 'kind', 'data'

  activityMessage: (item) ->
    return if !item
    return if !item.created_by

    if item.type is 'bulk_job'
      { total, failed_count } = item.objectNative?.data
      return if _.isUndefined(total) or _.isUndefined(failed_count)
      return App.i18n.translateContent('Bulk action completed for |%s| ticket(s): %s successful, %s failed', total, total - failed_count, failed_count)

    return "Unknown action for (#{@objectDisplayName()}/#{item.type}), extend activityMessage() of model."

  uiUrl: (item) ->
    undefined
