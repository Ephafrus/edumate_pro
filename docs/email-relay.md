# Sending email from the web portal

A browser cannot open a connection to a mail server. That is not a limitation
of this app or of any particular SMTP provider — sockets to port 587/465 are
simply not something JavaScript is allowed to do, for good reasons. So on the
web portal, SMTP settings can be saved but never used: messages queue in the
outbox and go out the next time somebody opens the app on Android, iOS,
Windows, macOS or Linux.

If the school runs on the web portal, that is not good enough. The fix is a
**relay**: a small HTTPS endpoint the school owns, which receives a message
and sends it. The browser can make an ordinary HTTPS request, so the portal
sends immediately.

Choose **HTTPS relay** under *Email settings*, paste the URL, and — strongly
recommended — set a shared secret.

## What the endpoint receives

A `POST` with `Content-Type: application/json`, and `Authorization: Bearer
<shared secret>` when one is set:

```json
{
  "to": "parent@example.com",
  "subject": "Fee statement — March 2026",
  "text": "Plain text body",
  "html": "<p>Optional HTML body</p>",
  "fromName": "Test Primary School",
  "fromAddress": "office@testprimary.co.za"
}
```

Answer **2xx** once the message is away. Any other status leaves the message
in the outbox to be retried, and the status and body are shown to the admin —
so return something that explains the problem.

## A relay you can paste in (Google Apps Script)

Free, no server to run, and it sends through the school's own Google account.
Its daily send limit is 100 messages on a free account and 1 500 on Workspace.

1. Go to <https://script.google.com> signed in as the school's account.
2. **New project**, and replace the contents of `Code.gs` with:

```javascript
// Shared secret — must match what you enter in Email settings.
const SECRET = 'change-me-to-something-long-and-random';

function doPost(e) {
  try {
    const auth = (e.parameter.token) ||
      ((e.postData && e.postData.type) ? getBearer(e) : '');
    if (auth !== SECRET) {
      return reply(401, { error: 'Bad or missing token' });
    }

    const body = JSON.parse(e.postData.contents);
    if (!body.to || !body.subject) {
      return reply(400, { error: 'to and subject are required' });
    }

    MailApp.sendEmail({
      to: body.to,
      subject: body.subject,
      body: body.text || '',
      htmlBody: body.html || undefined,
      name: body.fromName || undefined,
    });
    return reply(200, { ok: true });
  } catch (err) {
    return reply(500, { error: String(err) });
  }
}

function getBearer(e) {
  // Apps Script does not expose request headers, so the token is also
  // accepted as a query parameter — see the note below.
  return e.parameter.token || '';
}

function reply(status, payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
```

3. **Deploy → New deployment → Web app**
   - *Execute as*: **Me**
   - *Who has access*: **Anyone**
4. Copy the `/exec` URL.

**Apps Script cannot read the `Authorization` header**, so append the secret
to the URL instead:

```
https://script.google.com/macros/s/AKfy…/exec?token=change-me-to-something-long-and-random
```

Paste that whole URL into *Relay URL* and leave *Shared secret* blank. Treat
the URL as a password: anyone holding it can send mail as the school.

## Other options

Anything that accepts a POST works — a Cloudflare Worker or Vercel function
wrapping Resend/SendGrid/Postmark, an existing school API, or an automation
platform's webhook.

If you write your own, it must return the CORS headers that let the portal
call it:

```
Access-Control-Allow-Origin: https://your-school.web.app
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Allow-Methods: POST, OPTIONS
```

and answer `OPTIONS` preflight with 204. Without these the browser blocks the
request before it is sent, and *Send test email* will say so.

## Why not put a provider's API key straight in the app?

Because the app is a website. Anything it holds — an API key included — can be
read by anyone who opens it, and would let them send mail as the school. A
relay keeps the credential on a machine the school controls and gives it one
narrow job.

## Testing

*Email settings → Send test email* reports what actually happened: a 401 from
a wrong secret, a CORS refusal, a timeout, or the provider's own error text.
Every attempt — test or real — is recorded in the outbox with its status and
error.
