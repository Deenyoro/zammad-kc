# KC: Channel driver for the FreePBX phone integration.
#
# Zammad's generic channel loop fetches every active channel whose area ends
# in "::Account". FreePBX call activity is polled on its own schedule by
# Kc::PollFreepbxMissedCallsJob, so this driver opts out of that loop; without
# it, every fetch cycle would fail to resolve a driver and permanently mark
# the channel as errored.
#
# Outbound text messages are deliberately not implemented here. RingCentral
# owns SMS for the whole phone system, so replies to FreePBX-originated
# tickets are sent through the RingCentral channel (see Kc::OutboundSms).
class Channel::Driver::KcFreepbx

  def fetchable?(_channel = nil)
    false
  end

  # Nothing to fetch on Zammad's schedule; the KC scheduler job owns polling.
  def fetch(_options = nil, _channel = nil)
    { result: 'ok', notice: 'FreePBX is polled by the KC scheduler job.' }
  end

  def deliver(_options, _attr, _notification = false, channel: nil)
    raise 'KC FreePBX: text messages are sent through RingCentral, not FreePBX'
  end
end
