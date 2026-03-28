# KC: Disable session takeover — defense-in-depth frontend no-op.
#
# Sprockets loads files alphabetically via `require_tree ./controllers`.
# This file (session_taken_over_kc_disable.coffee) loads after
# session_taken_over.coffee and overwrites the 'session_taken_over'
# plugin config key with a no-op controller.
#
# Even if the backend patch is bypassed, this plugin will never send
# the session_takeover event or show the takeover modal.

class SessionTakeOverKcDisable extends App.Controller
  constructor: ->
    super
    # intentional no-op — session takeover is disabled

App.Config.set('session_taken_over', SessionTakeOverKcDisable, 'Plugins')
