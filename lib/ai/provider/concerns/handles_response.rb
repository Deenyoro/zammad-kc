# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Provider
  module Concerns::HandlesResponse
    extend ActiveSupport::Concern

    included do # rubocop:disable Metrics/BlockLength
      def handle_response(response, provider)
        message = case response.code.to_i
                  when 200..399
                    return handle_success(response, provider)
                  when 400
                    __('Invalid request - please check your input')
                  when 401
                    __('Invalid API key - please check your configuration')
                  when 402
                    __('Payment required - please top up your account')
                  when 403
                    __('Forbidden - you do not have permission to access this resource')
                  when 429
                    __('Rate limit exceeded - please wait a moment')
                  when 500
                    __('API server error - please try again')
                  when 502..503
                    __('API server unavailable - please try again later')
                  when 529
                    __('Service overloaded - please try again later')
                  else
                    __('An unknown error occurred')
                  end

        raise AI::Provider::ResponseError, message
      end

      private

      def handle_success(response, provider)
        case provider.name
        when 'AI::Provider::OpenAI'
          response.data['choices'].first['message']['content']
        when 'AI::Provider::Ollama'
          response.data['response']
        when 'AI::Provider::ZammadAI'
          response.data.first['response']
        end
      end
    end
  end
end
