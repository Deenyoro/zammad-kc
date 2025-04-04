# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TextSpellingAndGrammar < AI::Service
  private

  def options
    {
      temperature: 0.3,
    }
  end

  def cachable?
    false
  end

end
