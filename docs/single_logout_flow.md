# Single Logout Flow

This document explains how single logout works in this gem from start to end.

## What single logout means

Single logout, or SLO, means a user signs out once from CAS and every application using that CAS session should also sign the user out locally.

In this gem, local sign-out does not depend only on the browser heartbeat. The gem can also receive a server-to-server logout request from CAS and mark the CAS ticket as no longer valid.

## How to enable it in an app

Single logout should be controlled by configuration, because not every environment can accept back-channel POSTs from CAS.

Recommended initializer setup:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.single_logout_enabled = true
  config.sign_out_store = CasinoClientSessionGuard::TicketStores::RailsCacheStore.new
  config.sign_out_ttl = 12.hours
end
```

Recommended usage:

- Keep it enabled in staging and production when CAS can reach the app host.
- Use a shared cache or shared ticket store if you run multiple app nodes.
- Keep the engine mounted so the explicit `/logout` route exists, even though CAS may post to the original service URL instead.

Disable it when needed:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.single_logout_enabled = false
end
```

When disabled:

- The middleware will not intercept logout POSTs.
- The dedicated logout route returns `404 Not Found`.
- Session expiry still falls back to normal heartbeat and remote CAS validation.

## The main idea

The gem tracks one important value from CAS:

- The CAS service ticket stored in the Rails session.

When CAS later says that ticket is logged out, the gem stores that ticket in the configured sign-out store. After that:

- Heartbeat requests reject the session.
- Protected controller requests reject the session.
- The local Rails session is cleared.
- The browser is sent back to sign in again.

## Start to end flow

### 1. User signs in through CAS

CAS authenticates the user and sends the browser back to your Rails app.

Your app stores these values in session:

- CAS user
- CAS service URL
- CAS ticket
- Authenticated timestamp
- Heartbeat token

At this point the user is active in your app.

### 2. User keeps using the app

The gem protects requests in two ways:

- Page and XHR requests go through `Protectable`
- Browser heartbeat requests go through `HeartbeatsController`

If the CAS ticket is still valid, the session stays active.

### 3. User logs out from CAS

When the user logs out from CAS, the CAS server usually sends a POST request back to the original service URL that was tied to the CAS ticket.

This is important:

- CAS does not always call a dedicated logout endpoint.
- CAS often calls the exact service URL where that ticket was created.
- That service URL may be a normal page route such as an edit page, translations page, or admin screen.

This request is usually sent directly from CAS to your app, not from the browser.

The gem now handles this in two ways:

- A Rack middleware catches CAS single logout POSTs before Rails routing.
- The dedicated engine route can still process logout payloads directly.

Dedicated engine route:

```text
POST /logout
```

### 4. The gem reads the logout request

Because CAS may POST to arbitrary service URLs, the middleware checks every incoming POST request before your controller action runs.

If the request looks like a CAS single logout notification, the middleware handles it immediately and returns `200 OK`.

This avoids errors like:

- `404` when the service URL does not support POST
- `500` when the page action crashes on an unexpected CAS logout payload
- connection issues when the target app instance is down

The gem accepts logout tickets in these forms:

- `ticket` request parameter
- `logoutRequest` XML parameter
- Raw XML request body

From the XML payload, the gem reads every `SessionIndex` value it finds.

Why every value matters:

- Some CAS setups can send more than one ticket for the same service logout event.
- Invalidating only the first ticket would leave older or parallel issued tickets usable.

### 5. The gem marks each ticket as signed out

Every extracted ticket is stored in the configured `sign_out_store`.

Default behavior:

- Uses Rails cache
- Stores the ticket with a TTL
- Later checks whether the ticket was already invalidated

### 6. The next app request is blocked

When the browser sends the next request, the gem checks the ticket.

If that ticket was invalidated:

- The Rails session is cleared
- Heartbeat returns `401`
- XHR and Turbo requests return `401` with redirect headers
- Full page requests are redirected to CAS login

This means CAS controls the logout state even if the browser still has an old local session cookie.

## Scenarios handled by this gem

### Scenario 1: Standard heartbeat, session still valid

What happens:

- Browser sends heartbeat
- Token matches
- Local session exists
- CAS ticket is not in the invalidation store
- Remote validation passes

Result:

- Response is `200`
- Session validation timestamp is refreshed

### Scenario 2: Browser heartbeat after CAS logout

What happens:

- CAS already posted logout for the ticket
- Browser sends next heartbeat
- Gem sees the ticket in the invalidation store

Result:

- Local session is cleared
- Response is `401`
- Frontend can redirect user to sign in again

### Scenario 3: Turbo or AJAX request after CAS logout

What happens:

- Browser makes XHR or Turbo request
- `Protectable` checks the stored CAS ticket
- Ticket is already invalidated

Result:

- Local session is cleared
- Response is `401`
- `Turbo-Visit-Location` and `X-Session-Expired` headers are set

### Scenario 4: Full page request after CAS logout

What happens:

- Browser requests a normal page
- `Protectable` checks the stored CAS ticket
- Ticket is already invalidated

Result:

- Local session is cleared
- Request is treated as unauthenticated
- User is redirected to CAS login

### Scenario 5: CAS sends direct ticket param

Example:

```text
ticket=ST-123
```

Result:

- That ticket is invalidated immediately

### Scenario 6: CAS sends XML in `logoutRequest`

Example:

```xml
<samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
  <samlp:SessionIndex>ST-123</samlp:SessionIndex>
</samlp:LogoutRequest>
```

Result:

- The `SessionIndex` ticket is invalidated

### Scenario 7: CAS sends raw XML body

Some CAS servers post XML directly as the request body instead of form params.

Result:

- The gem reads `request.raw_post`
- Each `SessionIndex` is invalidated

### Scenario 8: CAS sends multiple `SessionIndex` values

Example:

```xml
<samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
  <samlp:SessionIndex>ST-123</samlp:SessionIndex>
  <samlp:SessionIndex>ST-456</samlp:SessionIndex>
</samlp:LogoutRequest>
```

Result:

- Both tickets are invalidated
- Any local session using either ticket will be rejected on the next request

### Scenario 9: CAS posts logout to the original service URL

Example service URLs from a real setup can look like these:

```text
/admin/sites/1play-uae/int/copy-of-1play-demo-v1-gb?locale=hu-HU
/admin/sites/1play-uae/int/copy-of-1play-demo-v1-gb/translations?locale=en-AE&page=1
```

What happens:

- CAS sends a POST to that page URL
- The Rails route may not support POST at all
- Without middleware, Rails would answer `404` or the page code could raise `500`

Result with this gem:

- Middleware sees the logout payload before routing
- The ticket or tickets are invalidated
- The middleware returns `200 OK`
- Your normal page controller action is never executed for that logout POST

### Scenario 10: Invalid logout payload

What happens:

- CAS request has no ticket
- Or XML cannot be parsed

Result:

- Response is `400 Bad Request`
- A warning is logged for XML parse errors

### Scenario 11: CAS cannot reach the service at all

What happens:

- CAS tries to POST the logout notification
- The app host is down, local server is stopped, or the port is closed

Example:

```text
Failed to open TCP connection to localhost:3000
```

Result:

- The gem cannot process the logout notification because the request never arrives
- CAS logs the delivery failure
- Any existing local session will only be rejected later when the browser sends another protected request or heartbeat and remote validation fails

This case cannot be solved only inside the gem. The app instance must be reachable by CAS.

## Why this matters

Without back-channel logout support, an app only learns about logout on the next remote validation or heartbeat cycle.

With this feature:

- CAS can notify the app immediately
- Old tickets are blocked quickly
- Stale sessions are cleared safely
- Multi-tab and delayed-browser cases are handled better
- CAS logout POSTs to normal service URLs no longer depend on those routes supporting POST

## Current limits

These are still outside the current implementation:

- Verifying that the logout request really came from CAS by source IP, signature, or shared secret
- Storing additional metadata such as logout time or service identifier
- Broadcasting logout events to other app nodes outside the selected cache/store backend
- Solving network-level delivery failures when CAS cannot connect to the application host

## Files involved

- `app/controllers/casino_client_session_guard/single_logouts_controller.rb`
- `lib/casino_client_session_guard/single_logout_request.rb`
- `lib/casino_client_session_guard/single_logout_middleware.rb`
- `app/controllers/casino_client_session_guard/heartbeats_controller.rb`
- `app/controllers/concerns/casino_client_session_guard/protectable.rb`
- `lib/casino_client_session_guard/session_manager.rb`
- `lib/casino_client_session_guard/ticket_stores/rails_cache_store.rb`

## Quick summary

In simple words:

1. CAS gives your app a ticket when the user signs in.
2. Your app keeps using that ticket while the session is active.
3. CAS later sends a logout POST, often to the original service URL.
4. Middleware or the logout controller reads one or more tickets from that POST.
5. The gem stores those tickets as invalid.
6. Any later heartbeat or protected request using those tickets is rejected.
7. The local session is cleared and the user must sign in again.