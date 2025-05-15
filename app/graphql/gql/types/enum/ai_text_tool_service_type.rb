# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module Gql::Types::Enum
  class AITextToolServiceType < BaseEnum
    description 'Available AI text tool services'

    build_string_list_enum(
      AI::Service.list
        .map { |klass| klass.name.demodulize.underscore }
        .select { |s| s.start_with?('text_') }
        .map { |s| s.delete_prefix('text_') }
        .sort
    )
  end
end
