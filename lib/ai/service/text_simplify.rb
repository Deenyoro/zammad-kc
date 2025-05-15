# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class AI::Service::TextSimplify < AI::Service
  private

  def options
    {
      temperature: 0.1,
    }
  end

  def cachable?
    false
  end

  def json_response?
    false
  end
end
