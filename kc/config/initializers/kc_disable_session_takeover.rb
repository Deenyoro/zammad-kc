# KC: Disable session takeover — allows multiple browser tabs per user.
#
# Zammad's legacy desktop-app enforces single-session-per-user via
# Sessions::Event::SessionTakeover. When a second tab connects, the backend
# broadcasts a `session_takeover` event to all other WebSocket sessions of
# the same user, causing them to show a modal and disconnect.
#
# This initializer redefines `Sessions::Event::SessionTakeover#run` as a
# no-op so the broadcast is never sent.

Rails.application.config.to_prepare do
  Sessions::Event::SessionTakeover.class_eval do
    def run
      Rails.logger.debug 'KC: Session takeover disabled — ignoring session_takeover event'
      nil
    end
  end

  Rails.logger.info 'KC: Session takeover disabled'
end
