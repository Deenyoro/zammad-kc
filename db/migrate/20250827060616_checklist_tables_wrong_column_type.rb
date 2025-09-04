# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class ChecklistTablesWrongColumnType < ActiveRecord::Migration[7.2]
  def change
    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    migrate_checklist_sorted_item_ids_column
    migrate_checklist_template_sorted_item_ids_column
  end

  private

  def migrate_checklist_sorted_item_ids_column
    return if ActiveRecord::Base.connection.columns(:checklists).find { |c| c.name == 'sorted_item_ids' }.type == :string

    change_column :checklists, :sorted_item_ids, :string, null: true, array: true

    Checklist.reset_column_information
  end

  def migrate_checklist_template_sorted_item_ids_column
    return if ActiveRecord::Base.connection.columns(:checklist_templates).find { |c| c.name == 'sorted_item_ids' }.type == :string

    change_column :checklist_templates, :sorted_item_ids, :string, null: true, array: true

    ChecklistTemplate.reset_column_information
  end
end
