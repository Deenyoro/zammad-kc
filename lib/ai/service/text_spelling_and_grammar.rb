# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TextSpellingAndGrammar < AI::Service
  private

  def options
    {
      temperature: 0.1,
    }
  end

  def json_response?
    false
  end
end
