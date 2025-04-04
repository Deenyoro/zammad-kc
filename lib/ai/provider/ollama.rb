# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Provider::Ollama < AI::Provider
  def request
    response = UserAgent.post(
      "#{config[:url]}/api/generate",
      {
        model:   options[:model] || 'llama3.2',
        system:  prompt_system,
        prompt:  prompt_user,
        stream:  false,
        format:  'json',
        options: {
          temperature: options[:temperature] || 0.2,
        }
      },
      {
        open_timeout:  4,
        read_timeout:  60,
        verify_ssl:    true,
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
      config[:url],
      {},
      {
        open_timeout:  4,
        read_timeout:  60,
        verify_ssl:    true,
        total_timeout: 60,
        log:           {
          facility: 'AI::Provider',
        },
      },
    )

    raise AI::Provider::ResponseError, __('API server not accessible') if response.code.to_i != 200

    nil
  end
end
