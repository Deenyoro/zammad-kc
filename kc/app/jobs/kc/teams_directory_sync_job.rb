# KC: Background job that imports Azure AD users from the tenant directory
# into Zammad as customers, linked to a specific organization.
#
# Triggered manually via the admin "Sync Now" button (POST sync_directory).
#
# For each Azure AD user:
#   - Matches by Authorization(provider: 'microsoft_teams', uid: ad_id) first
#   - Falls back to email match
#   - Creates or updates the Zammad user with name, email, department, org
#   - Creates/updates the Authorization record
#
# If the global setting kc_teams_directory_deactivate_stale is true,
# users with a microsoft_teams authorization in the target org who are
# NOT found in the current Azure AD listing will be deactivated.
#
# Safety:
#   - safe_constantize on KC classes
#   - Per-user rescue so one bad record doesn't abort the entire sync
#   - Stores sync stats in channel.options[:last_directory_sync]
class Kc::TeamsDirectorySyncJob < ApplicationJob
  def perform(channel_id)
    channel = Channel.find_by(id: channel_id, area: 'MicrosoftTeamsChat::Account')
    if channel.nil?
      Rails.logger.error "KC Teams Directory Sync: Channel #{channel_id} not found"
      return
    end

    options = (channel.options || {}).with_indifferent_access
    unless options[:directory_sync]
      Rails.logger.info "KC Teams Directory Sync: Channel #{channel_id} has directory_sync disabled, skipping"
      return
    end

    graph = build_graph_client(channel)
    organization = resolve_organization(channel, options)

    stats = { users_created: 0, users_updated: 0, users_deactivated: 0 }
    synced_user_ids = []

    graph.list_all_users do |batch|
      batch.each do |ad_user|
        next if ad_user['accountEnabled'] == false

        begin
          user, created = sync_user(ad_user, organization)
          synced_user_ids << user.id
          created ? stats[:users_created] += 1 : stats[:users_updated] += 1
        rescue => e
          Rails.logger.error "KC Teams Directory Sync: Failed to sync AD user #{ad_user['id']}: #{e.message}"
        end
      end
    end

    if Setting.get('kc_teams_directory_deactivate_stale') && organization
      stats[:users_deactivated] = deactivate_stale_users(organization, synced_user_ids)
    end

    # Store sync stats on channel
    channel.options[:last_directory_sync] = {
      completed_at:      Time.current.iso8601,
      users_created:     stats[:users_created],
      users_updated:     stats[:users_updated],
      users_deactivated: stats[:users_deactivated],
    }
    channel.save!

    Rails.logger.info "KC Teams Directory Sync: Channel #{channel_id} complete — " \
                      "created=#{stats[:users_created]}, updated=#{stats[:users_updated]}, deactivated=#{stats[:users_deactivated]}"
  end

  private

  def build_graph_client(channel)
    options = channel.options.with_indifferent_access
    graph_class = 'Kc::MicrosoftTeamsGraph'.safe_constantize
    raise 'MicrosoftTeamsGraph class not available' if graph_class.nil?

    graph = graph_class.new(
      client_id:     options[:client_id],
      client_secret: options[:client_secret],
      tenant_id:     options[:tenant_id],
      access_token:  options[:access_token],
      refresh_token: options[:refresh_token],
    )

    # Refresh token before sync to ensure valid access
    graph.refresh_access_token!
    channel.options[:access_token]  = graph.access_token
    channel.options[:refresh_token] = graph.refresh_token
    channel.save!

    graph
  end

  def resolve_organization(channel, options)
    org_id = options[:organization_id]
    if org_id.present?
      Organization.find_by(id: org_id)
    else
      # Auto-create org from tenant ID
      tenant_name = options[:tenant_id] || 'Microsoft Teams'
      Organization.find_or_create_by!(name: "Teams — #{tenant_name}") do |org|
        org.active = true
      end
    end
  end

  def sync_user(ad_user, organization)
    ad_id = ad_user['id']
    email = (ad_user['mail'].presence || ad_user['userPrincipalName']).to_s.downcase.strip
    display_name = ad_user['displayName'] || ''
    department = ad_user['department']

    firstname, lastname = split_name(display_name)

    # 1. Try to find by Authorization
    auth = Authorization.find_by(provider: 'microsoft_teams', uid: ad_id)
    user = auth&.user

    # 2. Fall back to email match
    if user.nil? && email.present?
      user = User.find_by(email: email)
    end

    created = false
    if user
      update_attrs = {}
      update_attrs[:firstname]       = firstname if firstname.present? && user.firstname.blank?
      update_attrs[:lastname]        = lastname if lastname.present? && user.lastname.blank?
      update_attrs[:department]      = department if department.present?
      update_attrs[:organization_id] = organization.id if organization
      update_attrs[:active]          = true unless user.active

      # Replace placeholder teams.local emails with real Azure AD email
      if email.present? && user.email.to_s.end_with?('@teams.local')
        # Only replace if no other user already has this email
        update_attrs[:email] = email unless User.where(email: email).where.not(id: user.id).exists?
      end

      user.update!(update_attrs) if update_attrs.present?
    else
      user = User.create!(
        firstname:       firstname,
        lastname:        lastname,
        email:           email.presence,
        department:      department,
        organization_id: organization&.id,
        active:          true,
        role_ids:        Role.where(name: 'Customer').pluck(:id),
        updated_by_id:   1,
        created_by_id:   1,
      )
      created = true
    end

    # Ensure Authorization record exists
    if auth.nil?
      Authorization.create!(
        user:     user,
        provider: 'microsoft_teams',
        uid:      ad_id,
        username: email.presence || display_name,
      )
    end

    [user, created]
  end

  def split_name(display_name)
    parts = display_name.to_s.strip.split(/\s+/, 2)
    [parts[0].to_s, parts[1].to_s]
  end

  def deactivate_stale_users(organization, synced_user_ids)
    # Find users in this org who have a microsoft_teams authorization
    # but were NOT seen in the current sync
    stale_users = User.joins(:authorizations)
                      .where(organization_id: organization.id, active: true)
                      .where(authorizations: { provider: 'microsoft_teams' })
                      .where.not(id: synced_user_ids)

    count = 0
    stale_users.find_each do |user|
      user.update!(active: false)
      count += 1
    rescue => e
      Rails.logger.error "KC Teams Directory Sync: Failed to deactivate user #{user.id}: #{e.message}"
    end
    count
  end
end
