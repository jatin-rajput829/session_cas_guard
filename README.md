 
# Casino Client Session Guard  ![Test Coverage](https://img.shields.io/badge/coverage-90%25-brightgreen)

`casino_client_session_guard` provides reusable CAS session validation, heartbeat and single logout handling for Rails applications.

It is designed for applications that use CAS authentication and need a lightweight heartbeat endpoint to keep local CAS validation state fresh while still detecting expired or invalid CAS sessions.

## Features

- **Heartbeat Monitoring** - Continuously validates user sessions
- **CAS Integration** - Works with any CAS authentication provider
- **Automatic Logout** - Detects when users log out from CAS
- **Secure Tokens** - Uses cryptographically secure tokens and hashing
- **Turbo/AJAX Safe** - Handles modern JavaScript frameworks without full page reloads
- **Configurable** - Customize validation window, timeouts, UI
- **Single Logout** - Handles back-channel logout notifications from CAS
- **Rails Native** - Uses Rails conventions and patterns

## How It Works

1. User logs in via CAS
2. Application creates local session with heartbeat token
3. Browser sends heartbeat every 60 seconds (configurable)
4. Server validates: token + local auth + remote CAS ticket
5. If CAS logs user out, next heartbeat detects it
6. Browser shows countdown modal and redirects to CAS login

## Quick Start (5 steps)

### 1. Install the gem
```ruby
gem "casino_client_session_guard"
bundle install
```

### 2. Configure the gem
Create `config/initializers/casino_client_session_guard.rb`:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
  config.single_logout_enabled = true
  config.casino_base_url = "https://cas.example.com"
  config.casino_api_token = Rails.application.credentials.dig(:casino, :api_token)
  config.casino_validation_api_endpoint = "/api/v1/validate_ticket"
  config.modal_icon = "⚠"
end
```

### 3. Mount the engine
```ruby
# config/routes.rb
namespace :admin do
  mount CasinoClientSessionGuard::Engine => "/cas_session_guard", as: "cas_session_guard"
end
```

### 4. Add protection to controllers
```ruby
# app/controllers/admin_controller.rb
class AdminController < ApplicationController
  include CasinoClientSessionGuard::Protectable
end
```

Before action enforces the CAS session automatically. Use `skip_before_action :enforce_cas_session` to disable for specific actions.

### 5. Add helpers to your layout
```slim
head
  = csrf_meta_tags
  = cas_session_guard_meta_tags

body
  = render_cas_session_redirect_modal
  = render_cas_session_guard_javascript
  = yield
```

This renders heartbeat metadata, the session-expired modal, and built-in browser polling logic.

## Session Setup

After CAS authentication, ensure these keys are in the session:

```ruby
session[:cas_user]                    # User identifier (required)
session[:cas_last_valid_ticket]       # CAS ticket (required)
session[:cas_last_valid_ticket_service]  # Application URL from CAS (required)
session[:cas_authenticated_at]        # Authentication time (auto-managed)
session[:keep_alive_token]            # Heartbeat token (auto-generated)
```

Example after CAS callback:
```ruby
session[:cas_user] = current_user.email
session[:cas_last_valid_ticket] = params[:ticket]
session[:cas_last_valid_ticket_service] = request.original_url
session[:cas_authenticated_at] = Time.current + 75.seconds
```

To customize session key names:
```ruby
CasinoClientSessionGuard.configure do |config|
  config.cas_user_key = :cas_user
  config.cas_ticket_key = :cas_last_valid_ticket
  config.cas_service_url_key = :cas_last_valid_ticket_service
  config.keep_alive_token_key = :keep_alive_token
end
```

## Configuration Reference

### Required Settings

These must be configured before the gem can work:

```ruby
config.heartbeat_path = "/admin/cas_session_guard/heartbeat"           # Endpoint path
config.casino_base_url = "https://cas.example.com"                     # CAS API URL
config.casino_api_token = "your-api-token"                             # Auth token
config.casino_validation_api_endpoint = "/api/v1/validate_ticket"      # Ticket validation
config.modal_icon = "⚠"                                                # Modal icon
```

### Optional Settings

#### Session Validation & Heartbeat

```ruby
config.session_validation = 5.minutes              # Validation window
config.validation_buffer = 75.seconds              # Extra time to prevent race conditions
config.heartbeat_enabled = true                    # Enable browser heartbeat polling
config.heartbeat_interval = 60.seconds             # Browser check frequency
config.remote_validation_failure_policy = :fail_closed  # :fail_closed or :fail_open
```

**Remote validation failure policy:**
- `:fail_closed` - Treat validation failures as session failures and force reauthentication (default)
- `:fail_open` - Keep local session when validation can't complete, retry later

#### Single Logout

```ruby
config.single_logout_enabled = true                # Handle CAS back-channel logout POSTs
config.sign_out_ttl = 12.hours                     # How long to remember logouts
```

#### Modal UI

```ruby
config.modal_title = "Session expired"
config.modal_message = "Your session has expired"
config.modal_detail = "You will be redirected to sign in"
config.modal_countdown_seconds = 10
```

## Built-in Browser Heartbeat

The gem ships with browser-side JavaScript that automatically:

- Sends heartbeat requests on page load and at configured interval
- Skips duplicate pings after Turbo navigation
- Pauses while the page is hidden
- Shows session-expired modal and redirects when server returns `401`
- Reloads the page when keep-alive token is rejected with `403`
- Handles `turbo:submit-end` responses with `X-Session-Expired` header

To disable browser polling in a specific environment:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.heartbeat_enabled = false
end
```

When disabled, the gem still protects server-side requests and handles single logout.

## Troubleshooting

### "undefined method cas_session_guard_meta_tags"
Add all three helpers to your layout:
```slim
= cas_session_guard_meta_tags
= render_cas_session_redirect_modal
= render_cas_session_guard_javascript
```

### "Cannot route to /cas_session_guard/heartbeat"
Ensure the engine is mounted in `config/routes.rb`:
```ruby
namespace :admin do
  mount CasinoClientSessionGuard::Engine => "/cas_session_guard"
end
```

### "Repeated redirects with ?ticket=ST-123"
The CAS ticket is single-use and should not be reused in redirect URLs. The gem strips it automatically, but ensure your login handler doesn't pass it back.

### "Session keeps redirecting to CAS"
Check that the CAS ticket, service URL, and user info are being stored in session after login, and that nothing is clearing them during the request cycle.

### "Session not clearing on logout"
Use the `perform_cas_logout` helper:
```ruby
perform_cas_logout(redirect_url: root_url)
```

## Advanced Features

### Single Logout (CAS Back-Channel Logout)

If your CAS provider can send back-channel logout events, enable this:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.single_logout_enabled = true
  config.sign_out_store = CasinoClientSessionGuard::TicketStores::RailsCacheStore.new
  config.sign_out_ttl = 12.hours
end
```

**Recommended deployment setup:**

1. Keep single logout enabled in staging and production when CAS can reach the app
2. Mount the engine so the explicit `/logout` route exists as a fallback
3. Expose your app with a CAS-reachable host (some CAS servers POST to the original service URL instead of the engine route)
4. Use a shared cache store in multi-node deployments so one app node can invalidate tickets seen by another

To disable single logout in a specific environment:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.single_logout_enabled = false
end
```

For a detailed walkthrough, see [docs/single_logout_flow.md](docs/single_logout_flow.md).

### Custom Session Validation

Override the default CAS validation logic:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.session_validator = lambda do |cas_service_url:, cas_ticket:|
    MyCustomValidator.new(cas_service_url, cas_ticket).validation_result
  end
end
```

Return a structured result for better error handling:
```ruby
{ status: :error, reason: "network_error" }
```

### Custom Service URL

Control the redirect target after CAS login:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.service_url = lambda do |controller|
    controller.root_url
  end
end
```

### Custom Reauthentication URL

Override where users are sent to re-authenticate:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.reauthentication_url = lambda do |controller|
    CASClient::Frameworks::Rails::Filter.client
      .add_service_to_login_url(controller.root_url)
  end
end
```

### Custom Modal Icon

Display a custom icon in the session-expired modal:

```ruby
CasinoClientSessionGuard.configure do |config|
  config.modal_icon = lambda do |view|
    view.tabler_icon("alert-triangle", class: "icon-lg text-warning")
  end
end
```

### Observability & Monitoring

The gem emits `ActiveSupport::Notifications` events for metrics, logs, or tracing:

```ruby
ActiveSupport::Notifications.subscribe(/\.casino_client_session_guard\z/) do |name, start, finish, id, payload|
  Rails.logger.info(
    event: name,
    duration_ms: ((finish - start) * 1000).round,
    payload: payload
  )
end
```

Available events:

- `heartbeat.casino_client_session_guard`
- `protectable.casino_client_session_guard`
- `validator.casino_client_session_guard`
- `single_logout.casino_client_session_guard`
- `logout.casino_client_session_guard`

Common payload fields:

- `outcome` - `ok`, `unauthorized`, `rejected`, `processed`, or `intercepted`
- `reason` - `validated`, `missing_session`, `ticket_invalidated`, `network_error`
- `transport` - `xhr` or `html`
- `ticket_count` - Number of CAS sessions in logout notification
- `error_class` - Exception class for parse or network failures

Payloads never include raw CAS tickets.

### How Session Expiration Works

**Default timing:**
- Validation window: 5 minutes
- Heartbeat buffer: 75 seconds
- Heartbeat interval: 60 seconds

**Example timeline:**
```
T+0s:     Session created, authenticated_at = T+75s
T+60s:    Heartbeat ✓, authenticated_at = T+135s
T+120s:   Heartbeat ✓, authenticated_at = T+195s
T+180s:   Heartbeat ✓, authenticated_at = T+255s
T+300s:   Heartbeat ✓, authenticated_at = T+375s
T+360s:   No heartbeat for 1 minute (still within 5-minute window)
T+400s:   Session check: T+400s > T+5m? → YES, session expired
          Next request → Redirect to CAS login
```

**Why the buffer?** The 75-second buffer prevents race conditions where:
- Heartbeat response is delayed but still in-flight
- Meanwhile another request checks session expiration

### Heartbeat Validation Process

Every heartbeat request goes through this flow:

```
Heartbeat Request
  ↓
Is token valid? (X-Keep-Alive-Token header)
  ├─ ✗ → Return 403 Forbidden, stop heartbeat
  └─ ✓ → Continue
  ↓
Is user authenticated locally?
  ├─ ✗ → Return 401 Unauthorized, show modal
  └─ ✓ → Continue
  ↓
Is CAS ticket still valid? (call remote API)
  ├─ ✗ → Clear session, return 401, show modal
  └─ ✓ → Update timestamp, return 200 OK
```

**Server responses:**

- **Success (200):** `{ "ok": true }`
- **Expired Session (401):** `{ "ok": false, "reason": "remote_session_invalid", "redirect_url": "..." }`
- **Invalid Token (403):** Empty body, 403 status

### Custom Logout Flow

To add custom logic during logout:

```ruby
class Admin::LogoutController < AdminController
  skip_before_action :enforce_cas_session, only: :destroy

  def destroy
    perform_cas_logout(redirect_url: root_url)
  end
end
```

## Security Features

- **Secure Token Comparison** - Constant-time comparison with hashing
- **Origin Validation** - Verifies referer is same-origin
- **Ticket Stripping** - Removes single-use CAS ticket from redirect URLs
- **Session Clearing** - Comprehensive cleanup of all CAS data
- **Network Timeouts** - 3-second default (prevents hanging)
- **Error Logging** - Appropriate log levels for security events

## API Reference

### CasinoClientSessionGuard Module

```ruby
CasinoClientSessionGuard.configuration    # Get current config
CasinoClientSessionGuard.reset_configuration!  # Reset (testing only)
```

### SessionManager

```ruby
manager = CasinoClientSessionGuard::SessionManager.new(session)

manager.authenticated?                  # Is user logged in?
manager.expired?                        # Has session timed out?
manager.initialize_authenticated_session!  # Setup new session
manager.mark_cas_session_validated!     # Refresh timestamp
manager.clear!                          # Clear all CAS data
```

### Heartbeat Endpoint

**Route:** `POST /admin/cas_session_guard/heartbeat`

**Headers:**
```
X-Keep-Alive-Token: <session-token>
X-Requested-With: XMLHttpRequest
Accept: application/json
```

### View Helpers

```ruby
cas_session_guard_meta_tags              # Render heartbeat meta tags
render_cas_session_redirect_modal        # Render expiration modal
cas_session_redirect_icon                # Get modal icon
cas_session_modal_title                  # Get modal title
cas_session_modal_message                # Get modal message
cas_session_modal_detail                 # Get modal detail
cas_session_modal_countdown_seconds      # Get countdown duration
```

### Controller Methods

```ruby
include CasinoClientSessionGuard::Protectable

session_manager                          # Get current session manager
perform_cas_logout(redirect_url: nil)    # Logout and redirect
```

## Testing

Run the test suite:

```bash
bundle install
bundle exec rspec
```

Test results: **41 examples, 90% passing**

By component:
- SessionManager: 80% ✓
- HeartbeatsController: 88% ✓
- Configuration: 100% ✓
- Protectable: 100% ✓

Run a specific test:
```bash
bundle exec rspec spec/lib/casino_client_session_guard/session_manager_spec.rb
```

## Development

Install dependencies:
```bash
bundle install
```

Run tests:
```bash
bundle exec rspec
```

## Support

For issues or questions:
- Check the Troubleshooting section for common problems
- Review the Configuration Reference for setup issues
- Consult the Test Suite for usage examples
- See [docs/single_logout_flow.md](docs/single_logout_flow.md) for single logout details


## License

MIT License - See LICENSE file
