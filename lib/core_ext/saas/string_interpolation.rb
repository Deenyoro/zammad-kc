# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

# Monkey patch for frozen literal string warning

require 'sass'

$VERBOSE = false

# rubocop:disable Lint/MissingCopEnableDirective
# rubocop:disable Style/StringLiterals
# rubocop:disable Style/HashSyntax

module Sass::Script::Tree
  class StringInterpolation < Node
    def _perform(environment)
      res = +""
      before = @before.perform(environment)
      res << before.value
      mid = @mid.perform(environment)
      res << (mid.is_a?(Sass::Script::Value::String) ? mid.value : mid.to_s(:quote => :none))
      res << @after.perform(environment).value
      opts(Sass::Script::Value::String.new(res, before.type))
    end
  end
end
