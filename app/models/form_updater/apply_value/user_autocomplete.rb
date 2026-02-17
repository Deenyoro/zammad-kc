# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class FormUpdater::ApplyValue::UserAutocomplete < FormUpdater::ApplyValue::Base

  def can_handle_field?(field:, field_attribute:)
    field_attribute&.data_option&.[]('relation') == 'User'
  end

  def map_value(field:, config:)
    user = User.find_by(id: config['value'])
    return if !user

    # Serialize user with organization relation and computed fields
    user_serialized = FormUpdater::Graphql::Serializers::User.serialize(user)

    result[field][:value] = user.id
    result[field][:options] = [{
      value:   user.id,
      label:   user.fullname.presence || user.login,
      heading: user.organization&.name,
      object:  user_serialized,
    }]
  end
end
