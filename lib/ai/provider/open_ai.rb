# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Provider::OpenAI < AI::Provider
  OPENAI_API_BASE_URL = 'https://api.openai.com/v1'.freeze

  def request
    response = UserAgent.post(
      "#{OPENAI_API_BASE_URL}/chat/completions",
      {
        model:           options[:model] || 'gpt-4o',
        messages:        [
          {
            role:    'system',
            content: prompt_system,
          },
          {
            role:    'user',
            content: prompt_user,
          },
        ],
        temperature:     options[:temperature] || 0.2,
        response_format: {
          type: 'json_object'
        },
        stream:          false,
        store:           false,
      },
      {
        open_timeout:  4,
        read_timeout:  60,
        verify_ssl:    true,
        bearer_token:  config[:token],
        total_timeout: 60,
        json:          true,
        log:           {
          facility: 'AI::Provider',
        },
      },
    )

    handle_response(response, self.class)
  end

  def self.accessible!(config)
    response = UserAgent.get(
      "#{OPENAI_API_BASE_URL}/models",
      {},
      {
        open_timeout:  4,
        read_timeout:  60,
        verify_ssl:    true,
        bearer_token:  config[:token],
        total_timeout: 60,
        json:          true,
        log:           {
          facility: 'AI::Provider',
        },
      },
    )

    raise AI::Provider::ResponseError, __('API server not accessible') if response.code.to_i != 200

    nil
  end
end
