# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class CoreWorkflow::Condition::IsGreaterThanOrEqualTo < CoreWorkflow::Condition::BaseOperator
  def check_operator
    :>=
  end
end
