# Copyright (C) 2012-2025 Zammad Foundation, https://zammad-foundation.org/

class TriggerAIAgentJob < AIJob
  include HasActiveJobLock

  # This affects wether a blip about ongoing AI Agent work is shown in the UI only.
  # Jobs themselves are not cancelled.
  EXPIRE_ONGOING_AGENTS = 1.hour

  attr_reader :ticket, :trigger, :article, :changes, :user_id, :execution_type, :event_type

  discard_on(Exception) do |job, e|
    Rails.logger.info 'An unexpected error occurred while executing TriggerAIAgentJob. Discarding job. See exception for further details.'
    Rails.logger.info e

    job.mark_as_gone!
  end

  retry_on Service::AI::Agent::Run::TemporaryError, attempts: 5, wait: lambda { |executions|
    executions * 10.seconds
  } do |job, e|
    Rails.logger.info 'AI Service encountered a temporary error, but it persisted for too long. Discarding job. See exception for further details.'
    Rails.logger.info e
    job.mark_as_gone!
  end

  discard_on(Service::AI::Agent::Run::PermanentError) do |job, e|
    Rails.logger.info 'AI Service encountered a permanent error. Discarding job. See exception for further details.'
    Rails.logger.info e

    job.mark_as_gone!
  end

  discard_on(ActiveJob::DeserializationError) do |job, e|
    Rails.logger.info 'Trigger, Ticket or Article may got removed before TriggerAIAgentJob could be executed. Discarding job. See exception for further details.'
    Rails.logger.info e

    job.mark_as_gone!
  end

  after_enqueue :mark_as_enqueued!
  after_perform :mark_as_gone!

  def lock_key
    @trigger = arguments[0]
    @ticket = arguments[1]

    # "TriggerAIAgentJob/123/Ticket/42/Trigger/123"
    "#{self.class.name}/#{ticket.id}/#{trigger.id}"
  end

  def perform(trigger, ticket, article, changes:, user_id:, execution_type:, event_type:)
    @trigger = trigger
    @ticket  = ticket
    @article = article

    # Following arguments currently are not used.
    # They're added for compatibility reasons to match the interface of TriggerWebhookJob.
    @changes    = changes
    @user_id    = user_id
    @execution_type = execution_type
    @event_type = event_type

    return if abort?

    Service::AI::Agent::Run
      .new(ai_agent:, ticket:, article:)
      .execute
  end

  def self.redis_key(ticket)
    "ai_agent_jobs_on_ticket_#{ticket.id}"
  end

  def self.working_on(ticket)
    redis.smembers(redis_key(ticket))
  rescue Redis::BaseConnectionError
    []
  end

  def self.working_on?(ticket, _ai_agent)
    working_on(ticket).any?
  end

  def mark_as_enqueued!
    # arguments are empty if it was not possible to deserialize them
    return if arguments.empty?

    @trigger = arguments[0]
    @ticket = arguments[1]

    self.class.redis.eval <<~LUA, keys: [self.class.redis_key(ticket)], argv: [ai_agent&.id, EXPIRE_ONGOING_AGENTS.to_i]
      redis.call('SADD', KEYS[1], ARGV[1])
      return redis.call('EXPIRE', KEYS[1], ARGV[2])
    LUA
  rescue Redis::BaseConnectionError # rubocop:disable Lint/SuppressedException
  end

  def mark_as_gone!
    # arguments are empty if it was not possible to deserialize them
    return if arguments.empty?

    @trigger = arguments[0]
    @ticket = arguments[1]

    self.class.redis.srem(self.class.redis_key(ticket), ai_agent&.id)
  rescue Redis::BaseConnectionError # rubocop:disable Lint/SuppressedException
  end

  def self.redis
    @redis ||= Zammad::Service::Redis.new
  end

  private

  def abort?
    if ai_agent_id.blank?
      log_wrong_trigger_config
      return true
    elsif ai_agent.blank?
      log_not_existing_ai_agent
      return true
    end

    false
  end

  def ai_agent_id
    @ai_agent_id ||= trigger.perform.dig('ai.ai_agent', 'ai_agent_id')
  end

  def ai_agent
    @ai_agent ||= AI::Agent.where(active: true).find_by(id: ai_agent_id)
  end

  def log_wrong_trigger_config
    Rails.logger.error "Can't find ai_agent_id for Trigger '#{trigger.name}' with ID #{trigger.id}"
  end

  def log_not_existing_ai_agent
    Rails.logger.error "Can't find AI Agent for ID #{ai_agent_id} configured in Trigger '#{trigger.name}' with ID #{trigger.id}"
  end
end
