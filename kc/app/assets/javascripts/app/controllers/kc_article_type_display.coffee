# KC: Channel icon and label for the KC article types in the legacy UI.
#
# The ticket zoom article view shows the article type as "Channel" with
# @Icon(type name) and @T(type name). The KC types (teams_chat_message,
# ringcentral_sms_message, freepbx_sms_message) have no icon in the sprite
# and no translation, so the row showed no icon and the raw type name.
#
# Without touching upstream files this:
#   - maps the KC type names to existing sprite icons (chat / sms) in
#     App.Utils.icon, and
#   - registers the readable label as the translation of the type name via
#     App.i18n.setMap, re-applied whenever the language (re)loads.
#
# Labels match the Vue desktop article type plugins
# (kc/app/frontend/apps/desktop/pages/ticket/components/TicketDetailView/article-type/plugins/kc_*.ts).

KC_ARTICLE_TYPES =
  teams_chat_message:      { icon: 'chat', label: __('Teams Chat') }
  ringcentral_sms_message: { icon: 'sms',  label: __('RingCentral SMS') }
  freepbx_sms_message:     { icon: 'sms',  label: __('FreePBX SMS') }

try
  if App.Utils?.icon && !App.Utils.kcArticleTypeIcon
    kcOriginalIcon = App.Utils.icon
    App.Utils.kcArticleTypeIcon = true
    App.Utils.icon = (name, className = '') ->
      name = KC_ARTICLE_TYPES[name].icon if name && KC_ARTICLE_TYPES.hasOwnProperty(name)
      kcOriginalIcon.call(App.Utils, name, className)
catch e
  console.warn '[KC] article type icon mapping failed', e

kcApplyArticleTypeLabels = ->
  try
    for name, meta of KC_ARTICLE_TYPES
      App.i18n.setMap(name, App.i18n.translatePlain(meta.label))
  catch e
    console.warn '[KC] article type label mapping failed', e

App.Event.bind('i18n:language:change', kcApplyArticleTypeLabels, 'kc-article-type-display')
kcApplyArticleTypeLabels()
