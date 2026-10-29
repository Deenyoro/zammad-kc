# KC: Registers the KC "new conversation" draft tabs (RingCentral SMS, FreePBX
# SMS, Teams chat) as taskbar entities, so both desktop UIs share them.
#
# Upstream collects the taskbar entities from the models that declare
# `taskbar_entities`. These drafts belong to no model - like the ticket create
# screen they are keyed "<prefix>-<id>" and keep their form in the task state -
# so the callbacks are added to Taskbar.taskbar_entities here instead. With
# that:
#   - the new desktop UI lists the tabs (TaskbarPolicy::Scope) and can store
#     them (the GraphQL TaskbarEntityType enum, the `callback` of the taskbar
#     item mutations and subscriptions),
#   - a draft started in one UI shows up, and restores, in the other: both use
#     the same task key, callback and state field names
#     (kc_conversation_draft.coffee / useKcConversationDraft.ts).
#
# Load order: Gql::Types::Enum::TaskbarEntityType reads Taskbar.taskbar_entities
# once, when the enum class is loaded (build_string_list_enum). kc_loader.rb
# prepends this module in a to_prepare block, which Rails runs before eager
# loading (production) and long before the first GraphQL request (development,
# test) - and never loads a GraphQL class itself.
#
# IMPORTANT: This module is *prepended* onto Taskbar.singleton_class by
# kc_loader.rb, so `super` is the upstream Taskbar.taskbar_entities.
module Kc
  module TaskbarConversationDraftEntities
    # Taskbar callback => task key prefix, as used by the legacy controllers.
    DRAFTS = {
      'KcNewSmsConversationContent'        => 'KcNewSmsScreen',
      'KcNewFreepbxSmsConversationContent' => 'KcNewFreepbxSmsScreen',
      'KcNewTeamsConversationContent'      => 'KcNewTeamsScreen',
    }.freeze

    def self.callbacks
      DRAFTS.keys
    end

    def self.key_prefixes
      DRAFTS.values
    end

    # Whether a task key names one of the drafts ("KcNewSmsScreen-<id>").
    def self.draft_key?(key)
      prefix, id = key.to_s.split('-', 2)

      key_prefixes.include?(prefix) && id.present?
    end

    def taskbar_entities
      super | Kc::TaskbarConversationDraftEntities.callbacks
    end
  end
end
