# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

module FormUpdater::Concerns::HasUserPermissions
  extend ActiveSupport::Concern

  def resolve
    prepare_initial_data if meta[:initial]

    super
  end

  private

  def prepare_initial_data
    result['role_ids']  = initial_role_ids
    result['group_ids'] = initial_group_ids
  end

  def initial_role_ids
    {
      # FIXME: The group permissions field may be masked by core workflow module:
      #   `CoreWorkflow::Custom::AdminShowGroupListForAgents`
      #   unless the value is included here.
      #   Note that `initialValue` makes it work only
      #   in subsequent requests, but not for the first one.
      #   More info here: https://github.com/zammad/coordination-desktop-view/issues/598
      # initialValue: object&.role_ids,
      value:   object&.role_ids,
      options: initial_role_options,
    }.compact
  end

  def initial_role_options
    Role
      .where(active: true)
      .reorder(id: :asc)
      .map do |elem|
        {
          value:       elem.id,
          label:       elem.name,
          description: elem.note,
        }
      end
  end

  def initial_group_ids
    {
      initialValue: object&.saved_group_ids_access_map&.map do |group_id, group_access|
        {
          key:         SecureRandom.uuid,
          groups:      [group_id],
          groupAccess: group_access.index_with(true),
        }
      end,
      options:      initial_group_options,
    }.compact
  end

  def initial_group_options
    FormUpdater::Relation::Group.new(
      context:,
      current_user:,
      filter_ids:   Group.pluck(:id),
    ).options
  end
end
