# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class BetaUi::SendFeedback < BaseMutation
    description 'Submits user feedback on the new BETA UI'

    argument :input, Gql::Types::Input::BetaUi::FeedbackInputType, required: true, description: 'Input for the feedback on BETA UI'

    field :success, Boolean, null: false, description: 'Was the submission successful?'

    def authorized?(...)
      Setting.get('ui_desktop_beta_switch') && super
    end

    def resolve(input:)
      {
        success: Service::BetaUi::SendFeedback.new(**input).execute,
      }
    end
  end
end
