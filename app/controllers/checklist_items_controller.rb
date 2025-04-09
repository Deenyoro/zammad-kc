# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class ChecklistItemsController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  def show
    model_show_render(Checklist::Item, existing_item_params)
  end

  def create
    model_create_render(Checklist::Item, new_item_params)
  end

  def create_bulk
    create_item_params = params.permit(:checklist_id, items: %i[text checked])

    checklist = Checklist.find(params[:checklist_id])

    created_items = create_item_params[:items].map do |item|
      checklist.items.create!(item)
    end

    render json: { success: true, checklist_item_ids: created_items.map(&:id) }, status: :created
  end

  def update
    model_update_render(Checklist::Item, existing_item_params)
  end

  def destroy
    model_destroy_render(Checklist::Item, existing_item_params)
  end

  private

  def new_item_params
    params.permit(:text, :checklist_id)
  end

  def existing_item_params
    params.permit(:text, :id, :checked)
  end
end
