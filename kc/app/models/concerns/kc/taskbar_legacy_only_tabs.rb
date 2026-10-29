# KC: Concern prepended into Taskbar to keep tabs that only the legacy desktop
# UI knows out of the taskbar subscriptions of the new desktop UI.
#
# The KC "new conversation" screens (RingCentral SMS, FreePBX SMS, Teams chat)
# are taskbar tabs of their own in the legacy UI, stored with callbacks like
# 'KcNewSmsConversationContent'. The new UI lists only the tabs whose callback
# is one of Taskbar.taskbar_entities (TaskbarPolicy::Scope), but its item
# subscription is pushed for every desktop taskbar - and serializing such an
# item fails, because its callback is no value of the TaskbarEntityType enum.
#
# IMPORTANT: This module is *prepended* (not included) by kc_loader.rb, so the
# overrides run before the upstream callbacks and call them through `super`.
module Kc
  module TaskbarLegacyOnlyTabs
    private

    def trigger_taskbar_item_create_subscriptions
      return if !kc_taskbar_entity_known?

      super
    end

    def trigger_taskbar_item_update_subscriptions
      return if !kc_taskbar_entity_known?

      super
    end

    def trigger_taskbar_item_destroy_subscriptions
      return if !kc_taskbar_entity_known?

      super
    end

    def kc_taskbar_entity_known?
      Taskbar.taskbar_entities.include?(callback)
    end
  end
end
