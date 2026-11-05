# SMS ticket blocklist

Administrators can manage **SMS ticket blocked numbers** under
**KC Extensions → RingCentral SMS → Settings**, or the corresponding system
setting `kc_sms_ticket_blocked_numbers`. Enter one number per line; commas and
semicolons also separate entries. Ten-digit national numbers use country code
+1; use an explicit +country code for international numbers. Empty disables the
blocklist. Removing a number allows future imports again.

The same list applies to RingCentral and FreePBX. Webhooks, fallback polling,
manual backfills, native-app outbound captures, and earlier-conversation context
all exclude a conversation when any participant is blocked. The driver checks
before creating a contact, ticket, article, or downloading attachments. Blocked
group conversations are excluded in full rather than exposing private replies
inside another participant's ticket.

This controls SMS ticket imports. It does not block SMS at the carrier, remove
messages from RingCentral/FreePBX, delete existing tickets, block voice calls, or
change manually composed Zammad messages. Automation can still exchange texts
using the provider API. Polling continues normally for other conversations.
Deployment-specific numbers belong in the setting, never in source code.

New installations load the setting through the KC seed hook. Existing databases
receive the same idempotent setting definition through migration
`20261104000001`. Changes are validated on the server, including direct API edits.

Run focused tests without a database:

```sh
gem install --no-document rspec:3.13.2 activesupport:8.1.4
ruby -S rspec --options /dev/null kc/spec/unit/sms_ticket_blocklist_spec.rb
```

The image build depends on this test job passing. These unit tests do not replace
a production deployment check of the setting and actual blocked message IDs.
