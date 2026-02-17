# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class FormUpdater::ApplyValue::OrganizationAutocomplete < FormUpdater::ApplyValue::Base

  def can_handle_field?(field:, field_attribute:)
    field_attribute&.data_option&.[]('relation') == 'Organization'
  end

  def map_value(field:, config:)
    organization = Organization.find_by(id: config['value'])
    return if !organization

    # Serialize organization
    organization_serialized = FormUpdater::Graphql::Serializers::Organization.serialize(organization)

    result[field][:value] = organization.id
    result[field][:options] = [{
      value:        organization.id,
      label:        organization.name,
      organization: organization_serialized,
    }]
  end
end
