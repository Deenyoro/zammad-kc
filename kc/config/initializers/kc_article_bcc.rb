# KC: Add bcc argument to the GraphQL ArticleInputType so the Vue UI can
# pass BCC recipients through the ticket update mutation.
#
# Safety: Wrapped in safe_constantize so the app boots even if upstream
# renames or removes the target class.

Rails.application.config.after_initialize do
  article_input = 'Gql::Types::Input::Ticket::ArticleInputType'.safe_constantize
  if article_input.nil?
    Rails.logger.warn 'KC: Gql::Types::Input::Ticket::ArticleInputType not found — skipping bcc argument'
    next
  end

  article_input.argument :bcc, [String], required: false, description: 'The article BCC address.'
  Rails.logger.info 'KC: Added bcc argument to ArticleInputType'
end
