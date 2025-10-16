# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

Zammad::Application.routes.draw do
  scope Rails.configuration.api_path do
    namespace :ai do
      namespace :analytics do
        resource :usages, only: [:update]
      end
    end
  end
end
