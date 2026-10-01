# FreePBX connector: SMS endpoints

Zammad's FreePBX text messaging (`kc_freepbx_sms_enabled`) talks only to the
KC PBX connector on the FreePBX host, never to the PBX's SMS module directly.
This is the contract the connector has to implement for texting; the call
endpoints (`/health`, `/calls`, `/extensions`, `/originate`, `/alert`,
`/resolve`) are unchanged. `Kc::FreepbxApi` in `kc/lib/kc/freepbx_api.rb` is
the client.

FreePBX has no SMS transport of its own. Texts reach the PBX through the
Sangoma SMS module (SIPStation / VoIP Innovations DIDs) or the open-source
[smsconnector](https://github.com/simontelephonics/smsconnector) module
(Twilio, Telnyx, Bandwidth, Flowroute, VoIP.ms, SignalWire and others). Both
store messages in the SMS module (`sms_messages`, `sms_dids`, `sms_routing`)
and both can send through `FreePBX::Sms()->sendMessage(...)`, so the connector
reads and writes there and Zammad does not care which provider is behind it.

All endpoints are JSON and authenticated with the connection's bearer token
(`Authorization: Bearer <token>`), like the call endpoints. Phone numbers are
E.164 (`+14125550123`); Zammad normalizes what it receives, but sending E.164
avoids surprises.

## `GET /sms/numbers`

DIDs the PBX can text from.

```json
{ "numbers": [ { "number": "+14125550100", "label": "Main line", "extension": "201" } ] }
```

`label` and `extension` are optional. Zammad caches this list on the
connection (refreshed by every poll and by the admin page's Test button); it
feeds the sender pickers and the missed-call auto-reply "from" list.

## `GET /sms`

Messages held by the SMS module, oldest first.

Query parameters:

| parameter       | meaning                                                         |
|-----------------|-----------------------------------------------------------------|
| `since`         | ISO 8601 timestamp; return messages created at or after it      |
| `since_minutes` | relative window, used when `since` is absent                    |
| `direction`     | `inbound`, `outbound`, or absent for both                       |
| `limit`         | maximum number of messages                                      |

```json
{
  "messages": [
    {
      "id": "sms:12345",
      "direction": "inbound",
      "from": "+14125550123",
      "to": ["+14125550100"],
      "text": "Hi, are you open today?",
      "created_at": "2026-09-29T14:02:11Z",
      "extension": null,
      "media": [
        { "id": "m1", "url": "/sms/media/m1", "content_type": "image/jpeg", "filename": "photo.jpg" }
      ]
    }
  ]
}
```

- `id` must be stable per message; Zammad deduplicates on it.
- `to` lists every recipient, so a group text carries them all.
- `extension` (optional) says which extension sent an outbound text from UCP
  or Sangoma Connect; Zammad shows it on the captured note.
- `media` is optional. `url` may be absolute or relative to the connector.

## `GET /sms/media/<id>`

Returns the media bytes with the right `Content-Type`. Used for every
`media[].url`.

## `POST /sms/send`

```json
{
  "from": "+14125550100",
  "to": ["+14125550123"],
  "text": "We are open until 6.",
  "media": [ { "filename": "map.png", "content_type": "image/png", "data_base64": "iVBORw0..." } ]
}
```

Response: `{ "id": "sms:12346" }`. Zammad sends the text and each attachment
as separate requests, text first. The returned id is stored on the article so
the outbound poll recognises the message as Zammad's own.

## Webhook (optional, recommended)

For instant delivery, POST each new message, in the same shape as an entry
of `GET /sms` (or `{ "messages": [ ... ] }` for several), to

```
POST https://<zammad>/api/v1/kc/freepbx_sms_webhook
X-KC-Token: <the connection's token>
```

The token identifies the connection; Zammad answers `401` for an unknown
token and `200 { "ok": true, "queued": n }` otherwise. Both directions are
welcome: inbound texts become customer articles, outbound texts sent outside
Zammad become internal notes. The per-minute poll keeps running as backup,
so a lost webhook only delays a message.

The Sangoma SMS module's own "SMS Webhook" feature and smsconnector's provider
callbacks can be used as the trigger; the connector translates their payload
into the shape above.

## `GET /contacts` (optional)

The PBX phonebook (Contact Manager), so SMS tickets and call notes can show
"Jane Smith (+14125550123)" instead of a bare number.

```json
{ "contacts": [ { "name": "Jane Smith", "numbers": ["+14125550123", "+14125550124"] } ] }
```

Zammad reads the whole list at most every 30 minutes and matches numbers on
their last ten digits. A connector without this endpoint answers `404`;
Zammad then simply uses the Zammad users and the RingCentral address book.
