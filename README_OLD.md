# CasinoClientSessionGuard

`casino_client_session_guard` provides reusable CAS session validation, heartbeat and Sign out handling for Rails applications.

It is designed for applications that use CAS authentication and need a lightweight heartbeat endpoint to keep local CAS validation state fresh while still detecting expired or invalid CAS sessions.

## Table of Contents

- [Features](#features)
- [Architecture Overview](#architecture-overview)
- [Main Components](#main-components)
- [Installation](#installation)
- [Mount the engine](#mount-the-engine)
- [Configuration](#configuration)
- [Controller Integration](#controller-integration)
- [Layout Integration](#layout-integration)
- [Heartbeat Behavior](#heartbeat-behavior)
- [Security Notes](#security-notes)
- [Testing & Development](#testing--development)
- [Common Errors](#common-errors)

## Features

- Rails Engine with heartbeat endpoint.
- Controller concern for CAS-protected controllers.
- Configurable session validation window.
- Configurable heartbeat interval.
- Configurable heartbeat route path.
- Built-in Casino/CAS ticket validator.
- Turbo/XHR-safe session-expiry handling.
- Secure heartbeat token validation.
- Safe CAS redirect target handling.
- Removes consumed `ticket` query param from redirect service URLs.
- Supports admin-scoped mounting such as `/admin/cas_session_guard/heartbeat`.

#### Test Results by Module:
| Module | Tests | Passing | %  |
|--------|-------|---------|-----|
| SessionManager | 10 | 8 | 80% |
| HeartbeatsController | 8 | 7 | 88% |
| Configuration | 2 | 2 | 100% |
| Protectable | 4 | 4 | 100% |
| CasinoSessionValidator | 3 | 0 | 0% |
| Routing | 1 | 0 | 0% |
| **TOTAL** | **41** | **35** | **85%** |

## Architecture Overview

### How it Works

The gem operates on a simple three-layer validation model:

1. **Local Session Layer** - Tracks authentication timestamp and validity window
2. **Browser Heartbeat Layer** - Periodically checks if session is still valid
3. **Remote CAS Layer** - Validates tickets with the CAS provider via API

```
Browser User
    ↓ (every 60 seconds)
Heartbeat Request (with token)
    ↓
HeartbeatsController validates:
  - Token is valid (same-origin check)
  - User is authenticated locally
  - CAS ticket is still valid remotely
    ↓
If all pass → Session timestamp updated
If any fail → Redirect to CAS login with modal
```

### Session Lifecycle

#### Session Creation
1. User authenticates with CAS (redirected to CAS server)
2. CAS redirects back with ticket parameter
3. CASClient gem validates ticket with CAS server
4. SessionManager initializes with:
   - User info (from CAS)
   - CAS ticket (single-use token)
   - Service URL (application URL where ticket was validated)
   - Authentication timestamp (used for expiration calculation)
   - Heartbeat token (used for browser requests)

#### Session Validation (Every Heartbeat)
1. Browser sends heartbeat with heartbeat token
2. Server validates token (prevents CSRF)
3. Server validates user is still authenticated locally
4. Server validates CAS ticket with remote CAS provider
5. If all valid, server updates authentication timestamp
6. Browser shows countdown modal if any validation fails

#### Session Expiration
1. No heartbeat received for 5+ minutes
2. SessionManager detects: `authenticated_at < 5.minutes.ago`
3. Session marked as expired
4. Next request rejected and user redirected to CAS login

## Main Components

### 1. SessionManager (`lib/casino_client_session_guard/session_manager.rb`)

Manages the CAS session state and lifecycle.

**Responsibilities:**
- Track session authentication timestamp
- Determine if session is expired (not validated in 5+ minutes)
- Initialize new authenticated sessions with tokens
- Clear all CAS-related session data on logout

**Key Methods:**
```ruby
manager = SessionManager.new(session)

manager.authenticated?              # Is user logged in?
manager.expired?                    # Has session exceeded validation window?
manager.initialize_authenticated_session!  # Setup new session with token
manager.mark_cas_session_validated! # Update timestamp (called after heartbeat)
manager.clear!                      # Remove all CAS session data
```

**Session Keys Managed:**
```
:cas_user                 # Current user identifier (set by host app)
:cas_last_valid_ticket    # CAS ticket for validation
:cas_service_url          # Application URL where ticket was issued
:cas_authenticated_at     # Timestamp + buffer (used for expiration)
:keep_alive_token         # Browser heartbeat token
```

### 2. Configuration (`lib/casino_client_session_guard/configuration.rb`)

Centralizes all gem configuration with sensible defaults.

**Default Values:**
```ruby
session_validation = 5.minutes      # Validation window
validation_buffer = 75.seconds      # Extra time to prevent race conditions
heartbeat_interval = 60.seconds     # Browser heartbeat frequency
heartbeat_path = "/cas_session_guard/heartbeat"  # Default endpoint
```

**Configuration Categories:**
- **Session Timing** - validation window, buffer, heartbeat interval
- **Session Keys** - customize where session data is stored
- **CAS Provider** - base URL, API token, validation endpoint
- **Sign-Out** - how to track logged-out sessions
- **Modal UI** - customizable expiration warning dialog

### 3. HeartbeatsController (`app/controllers/casino_client_session_guard/heartbeats_controller.rb`)

Endpoint that browser JavaScript calls periodically to validate the session.

**Validation Layers:**
1. **Token Validation** - Verify `X-Keep-Alive-Token` header (CSRF protection)
2. **Local Authentication** - Check if user is still authenticated locally
3. **Remote CAS Validation** - Ask CAS server if ticket is still valid

**Response Codes:**
- `200 OK` - Session is valid, timestamp updated
- `401 Unauthorized` - Session expired or CAS ticket invalid (includes redirect URL)
- `403 Forbidden` - Invalid heartbeat token (stops heartbeat from browser)

### 4. Protectable Concern (`app/controllers/concerns/casino_client_session_guard/protectable.rb`)

Rails concern for controllers that require CAS authentication.

**Main Methods:**
```ruby
include CasinoClientSessionGuard::Protectable  # Includes in controller

# Automatically enforces CAS auth on all actions
# Use skip_before_action :enforce_cas_session to disable for specific actions

perform_cas_logout(redirect_url: nil)  # Logout current user and redirect to CAS
```

**Security Features:**
- Detects and clears expired sessions
- Validates referer origin to prevent open redirects
- Strips CAS ticket from redirect URLs
- Handles AJAX/Turbo requests with special headers
- Seamlessly integrates with CASClient gem

### 5. CasinoSessionValidator (`lib/casino_client_session_guard/validators/casino_session_validator.rb`)

Validates CAS tickets with the remote CAS provider via HTTP API.

**How it Works:**
1. Makes HTTP GET request to CAS provider API
2. Sends authorization token in `Authorization` header
3. Sends ticket and service URL as query parameters
4. Expects JSON response with `{ "valid": true/false }`

**Network Handling:**
- **Timeouts:** 3 second default (fail-open if CAS is down)
- **Network Errors:** Logged as warnings (session stays valid)
- **Unexpected Errors:** Logged with full backtrace

### 6. RailsCacheStore (`lib/casino_client_session_guard/ticket_stores/rails_cache_store.rb`)

Tracks CAS tickets that have been signed out (logged out).

**How it Works:**
1. When user logs out, ticket is added to cache
2. Cache key: `"cas_session_guard:slo:invalidated:<ticket>"`
3. Cache TTL: 12 hours (configurable)
4. Prevents reuse of logged-out tickets

**Usage:**
```ruby
store = RailsCacheStore.new
store.invalidate(ticket: "TGT-123", ttl: 12.hours)
store.invalidated?(ticket: "TGT-123")  # => true
```

### 7. ApplicationHelper (`app/helpers/casino_client_session_guard/application_helper.rb`)

View helpers for integrating the heartbeat system into Rails layouts.

**Key Helpers:**
```erb
<%= cas_session_guard_meta_tags %>          <!-- Heartbeat configuration -->
<%= render_cas_session_redirect_modal %>    <!-- Expiration warning modal -->
<%= cas_session_redirect_icon %>            <!-- Icon for modal -->
```

## Default session policy

By default, the gem uses:

```ruby
session_validation = 5.minutes
validation_buffer = 75.seconds
heartbeat_interval = 60.seconds
```

On every successful heartbeat, the gem marks the CAS session as recently validated:

```ruby
session[:cas_authenticated_at] = Time.current + 75.seconds
```

A protected request expires the local CAS session when:

```ruby
session[:cas_authenticated_at] < session_validation.ago
```

So with the default configuration:

```text
Validation window: 5 minutes
Heartbeat buffer: 75 seconds
Heartbeat interval: 60 seconds

Timeline:
- Heartbeat at T+0s ✓ (timestamp set to T+75s)
- Session checked at T+60s ✓ (T+60s < T+75s, still valid)
- Session checked at T+120s ✓ (timestamp extended, now T+195s)
- No heartbeat for 6 minutes
- Session checked at T+360s ✗ (T+360s > T+5m, expires)

Browser Heartbeat
    ↓
HeartbeatsController
    ├─ Check Token (X-Keep-Alive-Token)
    │  └─ ❌ Forbidden → Stop heartbeat
    │  └─ ✅ Valid → Continue
    │
    ├─ Check Authentication (session[:cas_user])
    │  └─ ❌ Missing → Unauthorized + Redirect
    │  └─ ✅ Present → Continue
    │
    ├─ Check Remote CAS (call validator)
    │  └─ ❌ Ticket invalid → Clear session, Unauthorized
    │  └─ ✅ Ticket valid → Update timestamp
    │
    └─ Response 200 OK → Session remains active

```

## Installation

Add the gem to the host application:

```ruby
gem "casino_client_session_guard"
```

If developing locally:

```ruby
gem "casino_client_session_guard", path: "../casino_client_session_guard"
```

Then run:

```bash
bundle install
```

## Mount the engine

If the heartbeat is only used inside the admin area, mount the engine inside your admin routes.

```ruby name=config/routes/admin.rb
namespace :admin do
  root to: "sites#index"

  mount CasinoClientSessionGuard::Engine => "/cas_session_guard", as: "cas_session_guard"

  # Other admin routes...
end
```

This creates the heartbeat URL:

```text
/admin/cas_session_guard/heartbeat
```

The internal gem route remains:

```ruby name=config/routes.rb
CasinoClientSessionGuard::Engine.routes.draw do
  get "heartbeat", to: "heartbeats#show", as: :heartbeat
end
```

After changing routes, restart Rails and verify:

```bash
bin/rails routes | grep heartbeat
```

## Configuration

Create an initializer:

```ruby name=config/initializers/cas_session_guard.rb
CasinoClientSessionGuard.configure do |config|
  # Session timing configuration
  config.session_validation = 5.minutes        # How often to re-validate
  config.validation_buffer = 75.seconds        # Extra time for safety
  config.heartbeat_interval = 60.seconds       # Browser check frequency

  # Because the engine is mounted inside the admin namespace.
  config.heartbeat_path = "/admin/cas_session_guard/heartbeat"

  # Session keys used by the host application.
  config.cas_user_key = :cas_user
  config.cas_ticket_key = :cas_last_valid_ticket
  config.cas_service_url_key = :cas_service_url
  config.keep_alive_token_key = :keep_alive_token

  # Casino/CAS validator configuration - connects to CAS provider
  config.casino_base_url = Rails.application.credentials.dig(:casino, :base_url)
  config.casino_api_token = Rails.application.credentials.dig(:casino, :internal_api_token)
  config.casino_validation_api_endpoint = "/api/v1/validate_ticket"

  # Safe service URL used when the gem needs to send the user back through CAS
  config.service_url = lambda do |controller|
    controller.admin_root_url
  end

  # Final reauthentication URL returned to the browser on heartbeat expiry
  config.reauthentication_url = lambda do |controller|
    service_url = controller.admin_root_url
    CASClient::Frameworks::Rails::Filter.client
      .add_service_to_login_url(service_url)
  end

  # Session expiration warning modal
  config.modal_title = "Session expired"
  config.modal_message = "Your CAS session is no longer active."
  config.modal_detail = "For security, you will be redirected to sign in again."
  config.modal_countdown_seconds = 10
  config.modal_redirecting_text = "Redirecting in seconds"
  config.modal_icon = lambda do |view|
    view.content_tag(:span, "⚠", class: "text-warning")
  end
end
```

### Required Configuration

These settings MUST be configured for the gem to work:

| Setting | Example | Purpose |
|---------|---------|---------|
| `heartbeat_path` | `/admin/cas_session_guard/heartbeat` | Where browser sends heartbeats |
| `casino_base_url` | `https://cas.example.com` | CAS provider API endpoint |
| `casino_api_token` | `abc123xyz...` | Authorization token for CAS API |
| `casino_validation_api_endpoint` | `/api/v1/validate_ticket` | Relative path for ticket validation |
| `modal_icon` | `"⚠"` or lambda | Icon shown in expiration modal |

All other settings have sensible defaults.

## Dynamic configuration

These values are runtime configuration values, not hardcoded constants:

```ruby
config.session_validation = 5.minutes
config.validation_buffer = 75.seconds
config.heartbeat_interval = 60.seconds
config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
```

The defaults live inside the gem, but the host application can override them through the initializer.

Changing the initializer requires restarting the Rails server.

## Built-in Casino session validator

The gem includes a reusable validator:

```ruby
CasinoClientSessionGuard::Validators::CasinoSessionValidator
```

It validates the current CAS service URL and ticket through the configured Casino API.

Expected API endpoint:

```text
GET /api/v1/validate_ticket
```

Expected response:

```json
{
  "valid": true
}
```

The validator sends:

```text
Authorization: Bearer <casino_api_token>
Accept: application/json
```

With query params:

```text
cas_service_url=<service-url>
cas_ticket=<ticket>
```

The gem default validator is equivalent to:

```ruby
CasinoClientSessionGuard::Validators::CasinoSessionValidator.new(
  cas_service_url: cas_service_url,
  cas_ticket: cas_ticket
).valid?
```

If every project uses the same Casino API, no app-level `CasinoSessionValidator` service file is required.

## Required session values

After successful CAS authentication, the host application must have these session values:

```ruby
session[:cas_user]
session[:cas_last_valid_ticket]
session[:cas_service_url]
session[:cas_authenticated_at]
session[:keep_alive_token]
```

The gem can initialize some values, but the host application or CAS integration must ensure that the CAS user, ticket, and service URL are available.

Example after CAS callback:

```ruby
session[:cas_user] = current_cas_user
session[:cas_last_valid_ticket] = params[:ticket]
session[:cas_service_url] = request.base_url + request.path
session[:cas_authenticated_at] = Time.current + CasinoClientSessionGuard.configuration.validation_buffer
session[:keep_alive_token] ||= SecureRandom.hex(32)
```

Important: do not use the browser heartbeat token as the CAS ticket. The heartbeat token is only a same-origin request protection token.

## Controller integration

Include the concern in the controller that should be protected.

```ruby name=app/controllers/admin_controller.rb
class AdminController < ApplicationController
  include CasinoClientSessionGuard::Protectable

  before_action :update_admin_user
  before_action :load_nav_sites

  helper_method :current_user
end
```

No override method is required.

Do **not** add this unless you have explicitly customized the concern to call it:

```ruby
def perform_cas_authentication
  CASClient::Frameworks::Rails::Filter.filter(self)
end
```

The gem concern handles the CAS filter flow internally.

### Local application logout

Controllers that include `CasinoClientSessionGuard::Protectable` can use the gem's logout helper:

```ruby name=app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < AdminController
    skip_before_action :enforce_cas_session, only: :logout

    def logout
      perform_cas_logout(redirect_url: admin_root_url)
    end
  end
end
```

`perform_cas_logout` performs these steps:

```text
1. Saves the current CAS ticket.
2. Clears local CasinoClientSessionGuard session values.
3. Marks the ticket as signed out in the sign-out store.
4. Redirects the browser to the CAS logout endpoint.
```

Saving the ticket before clearing the session is important because clearing the session removes the configured CAS ticket value.

## Layout integration

Add the heartbeat metadata to the admin layout.

For Slim:

```slim name=app/views/layouts/admin.html.slim
head
  = csrf_meta_tags

  = cas_session_guard_meta_tags
```

If your layout already has a `head` block, add only the meta tags inside the existing block.

### 2. Render the heartbeat meta tags

Add the following helper inside the `<head>` element of the application layout:

```slim name=app/views/layouts/application.html.slim
head
  = cas_session_guard_meta_tags
```

The helper renders these three meta tags:

```slim name=app/views/layouts/application.html.slim
meta name="cas-session-guard-token" content=session[:keep_alive_token].to_s
meta name="cas-session-guard-heartbeat-url" content=CasinoClientSessionGuard.configuration.heartbeat_path
meta name="cas-session-guard-heartbeat-interval" content=(CasinoClientSessionGuard.configuration.heartbeat_interval.to_i * 1000)
```

They provide the following information to the gem's JavaScript:

| Meta tag | Purpose |
|---|---|
| `cas-session-guard-token` | Identifies the current browser session when sending a heartbeat. |
| `cas-session-guard-heartbeat-url` | Specifies the URL called by the heartbeat. |
| `cas-session-guard-heartbeat-interval` | Specifies how often the heartbeat runs, in milliseconds. |

For example, the generated HTML may look like:

```html
<meta name="cas-session-guard-token" content="abc123">
<meta name="cas-session-guard-heartbeat-url" content="/admin/cas_session_guard/heartbeat">
<meta name="cas-session-guard-heartbeat-interval" content="60000">
```

The application should use the helper instead of writing these tags manually. This keeps the values synchronized with `CasinoClientSessionGuard.configure`.

### 3. Render the session redirect modal

Render the gem's modal inside the `<body>` element:

```slim name=app/views/layouts/application.html.slim
body
  = render_cas_session_redirect_modal
  = yield
```

The modal uses the values configured in `config/initializers/cas_session_guard.rb`.

For example:

```text
Session expired

Your CAS session is no longer active.
For security, you will be redirected to sign in again.

10

Redirecting in seconds
```

The modal is initially hidden. The gem's JavaScript displays it when the heartbeat determines that the CAS session is no longer valid.

### Complete layout example

A simple application layout looks like this:

```slim name=app/views/layouts/application.html.slim
doctype html
html
  head
    title My application

    = csrf_meta_tags
    = csp_meta_tag
    = cas_session_guard_meta_tags

  body
    = render_cas_session_redirect_modal
    = yield
```

### JavaScript setup

Import the heartbeat JavaScript from the application entrypoint:

```javascript name=app/javascript/application.js
import "cas_session_guard/heartbeat";
```

The heartbeat JavaScript reads the values generated by `cas_session_guard_meta_tags`.

It uses:

```javascript name=app/javascript/cas_session_guard/heartbeat.js
const token = document.querySelector(
  'meta[name="cas-session-guard-token"]'
)?.content;

const heartbeatUrl = document.querySelector(
  'meta[name="cas-session-guard-heartbeat-url"]'
)?.content;

const heartbeatInterval = Number.parseInt(
  document.querySelector(
    'meta[name="cas-session-guard-heartbeat-interval"]'
  )?.content,
  10
);
```

When the heartbeat response reports an expired session, the JavaScript finds:

```html
<div id="session-redirect-modal">
```

and displays the configured modal.

### How the complete flow works

```text
The Rails layout renders the heartbeat meta tags
  ↓
The Rails layout renders the hidden modal
  ↓
The gem's JavaScript reads the heartbeat configuration
  ↓
JavaScript checks the session at the configured interval
  ↓
The server reports that the CAS session has expired
  ↓
JavaScript displays the modal
  ↓
The configured countdown starts
  ↓
The browser redirects the user
```

### Important

Both helpers must be present in the layout:

```slim name=app/views/layouts/application.html.slim
= cas_session_guard_meta_tags
= render_cas_session_redirect_modal
```

If the meta tags are missing, the JavaScript cannot determine the heartbeat URL, token, or interval.

If the modal is missing, the JavaScript redirects immediately instead of showing the countdown.

## Heartbeat behavior

The JavaScript heartbeat:

1. Reads the heartbeat URL from:

   ```html
   <meta name="cas-session-guard-heartbeat-url">
   ```

2. Reads the heartbeat token from:

   ```html
   <meta name="cas-session-guard-token">
   ```

3. Sends a request every configured interval.

4. Sends:

   ```text
   X-Keep-Alive-Token: <token>
   X-Requested-With: XMLHttpRequest
   Accept: application/json
   ```

5. On `200`, the session remains active.

6. On `401`, the browser navigates to the returned `redirect_url`.

7. On `403`, the heartbeat stops because the token is invalid.

## Heartbeat endpoint responses

Successful heartbeat:

```json
{
  "ok": true
}
```

Unauthenticated or invalid remote CAS session:

```json
{
  "ok": false,
  "reason": "remote_session_invalid",
  "redirect_url": "http://localhost:3000/login?service=http%3A%2F%2Flocalhost%3A3001%2Fadmin"
}
```

Invalid heartbeat token:

```text
403 Forbidden
```

## Safe redirect target handling

The gem must never send a consumed CAS ticket back as part of the CAS service URL.

Bad:

```text
/admin?ticket=ST-123
```

Good:

```text
/admin
```

The concern strips the `ticket` query param before building a CAS redirect target.

The safe redirect target priority is:

```text
1. Same-origin Referer, if present and valid
2. Current request URL
3. Configured service URL
4. Application base URL
```

Before returning the URL, the gem removes:

```text
ticket
```

This prevents CAS ticket reuse loops.

## Clearing session state

When the gem clears CAS session state, it removes the configured keys:

```ruby
session.delete(config.cas_user_key)
session.delete(:cas_authenticated_at)
session.delete(config.cas_ticket_key)
session.delete(config.cas_service_url_key)
session.delete(config.keep_alive_token_key)
```

`clear!` may return the last deleted value if written as sequential `session.delete` calls. That return value does not mean the session was not cleared.

## Common errors

### `undefined local variable or method cas_session_guard`

This happens if the layout uses:

```slim
meta name="cas-session-guard-heartbeat-url" content=cas_session_guard.heartbeat_path
```

but the engine route proxy is not available.

Use the configured path instead:

```slim
meta name="cas-session-guard-heartbeat-url" content=CasinoClientSessionGuard.configuration.heartbeat_path
```

### `/cas_session_guard/heartbeat` goes to `handle_invalid_locale`

This means the engine is not mounted at `/cas_session_guard`, or your app has a locale/catch-all route that captures the request.

If the heartbeat is admin-only, mount inside admin routes:

```ruby
namespace :admin do
  mount CasinoClientSessionGuard::Engine => "/cas_session_guard", as: "cas_session_guard"
end
```

Then configure:

```ruby
config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
```

### Repeated CAS redirects with `?ticket=...`

This usually means the CAS service URL includes an already-consumed ticket:

```text
/admin?ticket=ST-123
```

The service URL must remove the `ticket` query param before redirecting to CAS.

## Testing & Development

### Running Tests

```bash
bundle exec rspec
```

### Test Coverage

The gem includes comprehensive test coverage for:
- Session lifecycle (creation, validation, expiration, clearing)
- Heartbeat validation (token, authentication, remote CAS)
- Configuration (defaults, overrides, validation)
- Controller integration (protected actions, redirects)
- Session validator (network success, failures, timeouts)
- Redirect safety (ticket stripping, origin validation)

To run specific test files:

```bash
bundle exec rspec spec/lib/casino_client_session_guard/session_manager_spec.rb
bundle exec rspec spec/lib/casino_client_session_guard/validators/casino_session_validator_spec.rb
bundle exec rspec spec/controllers/casino_client_session_guard/heartbeats_controller_spec.rb
```

## Security notes

- The heartbeat token is not a CAS ticket.
- The heartbeat token should be random and stored in the Rails session.
- The CAS ticket should not be exposed to JavaScript.
- The remote validator must return `false` on network errors unless the application intentionally chooses a fail-open policy.
- The gem removes consumed `ticket` params from redirect service URLs to avoid CAS ticket reuse loops.
- Always use HTTPS in production for CAS communication.
- Validate that the CAS service URL matches your application domain.
- Keep the Casino API token secure (store in credentials, not code).


Add the gem to the host application:

```ruby
gem "casino_client_session_guard"
```

If developing locally:

```ruby
gem "casino_client_session_guard", path: "../casino_client_session_guard"
```

Then run:

```bash
bundle install
```

## Mount the engine

If the heartbeat is only used inside the admin area, mount the engine inside your admin routes.

```ruby name=config/routes/admin.rb
namespace :admin do
  root to: "sites#index"

  mount CasinoClientSessionGuard::Engine => "/cas_session_guard", as: "cas_session_guard"

  # Other admin routes...
end
```

This creates the heartbeat URL:

```text
/admin/cas_session_guard/heartbeat
```

The internal gem route remains:

```ruby name=config/routes.rb
CasinoClientSessionGuard::Engine.routes.draw do
  get "heartbeat", to: "heartbeats#show", as: :heartbeat
end
```

After changing routes, restart Rails and verify:

```bash
bin/rails routes | grep heartbeat
```

## Configuration

Create an initializer:

```ruby name=config/initializers/cas_session_guard.rb
CasinoClientSessionGuard.configure do |config|
  config.session_validation = 5.minutes
  config.validation_buffer = 75.seconds
  config.heartbeat_interval = 60.seconds

  # Because the engine is mounted inside the admin namespace.
  config.heartbeat_path = "/admin/cas_session_guard/heartbeat"

  # Session keys used by the host application.
  config.cas_user_key = :cas_user
  config.cas_ticket_key = :cas_last_valid_ticket
  config.cas_service_url_key = :cas_service_url
  config.keep_alive_token_key = :keep_alive_token

  # Casino/CAS validator configuration.
  config.casino_base_url = Rails.application.credentials.dig(:casino, :base_url)
  config.casino_api_token = Rails.application.credentials.dig(:casino, :internal_api_token)

  # Safe service URL used when the gem needs to send the user back through CAS.
  config.service_url = lambda do |controller|
    controller.admin_root_url
  end

  # Final reauthentication URL returned to the browser on heartbeat expiry.
  config.reauthentication_url = lambda do |controller|
    service_url = controller.admin_root_url

    CASClient::Frameworks::Rails::Filter.client
      .add_service_to_login_url(service_url)
  end
end
```

## Dynamic configuration

These values are runtime configuration values, not hardcoded constants:

```ruby
config.session_validation = 5.minutes
config.validation_buffer = 75.seconds
config.heartbeat_interval = 60.seconds
config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
```

The defaults live inside the gem, but the host application can override them through the initializer.

Changing the initializer requires restarting the Rails server.

## Built-in Casino session validator

The gem includes a reusable validator:

```ruby
CasinoClientSessionGuard::Validators::CasinoSessionValidator
```

It validates the current CAS service URL and ticket through the configured Casino API.

Expected API endpoint:

```text
GET /api/v1/validate_ticket
```

Expected response:

```json
{
  "valid": true
}
```

The validator sends:

```text
Authorization: Bearer <casino_api_token>
Accept: application/json
```

With query params:

```text
cas_service_url=<service-url>
cas_ticket=<ticket>
```

The gem default validator is equivalent to:

```ruby
CasinoClientSessionGuard::Validators::CasinoSessionValidator.new(
  cas_service_url: cas_service_url,
  cas_ticket: cas_ticket
).valid?
```

If every project uses the same Casino API, no app-level `CasinoSessionValidator` service file is required.

## Required session values

After successful CAS authentication, the host application must have these session values:

```ruby
session[:cas_user]
session[:cas_last_valid_ticket]
session[:cas_service_url]
session[:cas_authenticated_at]
session[:keep_alive_token]
```

The gem can initialize some values, but the host application or CAS integration must ensure that the CAS user, ticket, and service URL are available.

Example after CAS callback:

```ruby
session[:cas_user] = current_cas_user
session[:cas_last_valid_ticket] = params[:ticket]
session[:cas_service_url] = request.base_url + request.path
session[:cas_authenticated_at] = Time.current + CasinoClientSessionGuard.configuration.validation_buffer
session[:keep_alive_token] ||= SecureRandom.hex(32)
```

Important: do not use the browser heartbeat token as the CAS ticket. The heartbeat token is only a same-origin request protection token.

## Controller integration

Include the concern in the controller that should be protected.

```ruby name=app/controllers/admin_controller.rb
class AdminController < ApplicationController
  include CasinoClientSessionGuard::Protectable

  before_action :update_admin_user
  before_action :load_nav_sites

  helper_method :current_user
end
```

No override method is required.

Do **not** add this unless you have explicitly customized the concern to call it:

```ruby
def perform_cas_authentication
  CASClient::Frameworks::Rails::Filter.filter(self)
end
```

The gem concern handles the CAS filter flow internally.

### Local application logout

Controllers that include `CasinoClientSessionGuard::Protectable` can use the gem's logout helper:

```ruby name=app/controllers/admin/dashboard_controller.rb
module Admin
  class DashboardController < AdminController
    skip_before_action :enforce_cas_session, only: :logout

    def logout
      perform_cas_logout(redirect_url: admin_root_url)
    end
  end
end
```

`perform_cas_logout` performs these steps:

```text
1. Saves the current CAS ticket.
2. Clears local CasinoClientSessionGuard session values.
3. Marks the ticket as signed out in the sign-out store.
4. Redirects the browser to the CAS logout endpoint.
```

Saving the ticket before clearing the session is important because clearing the session removes the configured CAS ticket value.

## Layout integration

Add the heartbeat metadata to the admin layout.

For Slim:

```slim name=app/views/layouts/admin.html.slim
head
  = csrf_meta_tags

  meta name="cas-session-guard-token" content=session[:keep_alive_token].to_s

  meta name="cas-session-guard-heartbeat-url" content=CasinoClientSessionGuard.configuration.heartbeat_path

  meta name="cas-session-guard-heartbeat-interval" content=(CasinoClientSessionGuard.configuration.heartbeat_interval.to_i * 1000)
```

If your layout already has a `head` block, add only the meta tags inside the existing block.

## JavaScript installation

Because Rails gems are not automatically resolved as JavaScript modules by esbuild, copy the heartbeat JavaScript into the host application.


## Heartbeat behavior

The JavaScript heartbeat:

1. Reads the heartbeat URL from:

   ```html
   <meta name="cas-session-guard-heartbeat-url">
   ```

2. Reads the heartbeat token from:

   ```html
   <meta name="cas-session-guard-token">
   ```

3. Sends a request every configured interval.

4. Sends:

   ```text
   X-Keep-Alive-Token: <token>
   X-Requested-With: XMLHttpRequest
   Accept: application/json
   ```

5. On `200`, the session remains active.

6. On `401`, the browser navigates to the returned `redirect_url`.

7. On `403`, the heartbeat stops because the token is invalid.

## Heartbeat endpoint responses

Successful heartbeat:

```json
{
  "ok": true
}
```

Unauthenticated or invalid remote CAS session:

```json
{
  "ok": false,
  "reason": "remote_session_invalid",
  "redirect_url": "http://localhost:3000/login?service=http%3A%2F%2Flocalhost%3A3001%2Fadmin"
}
```

Invalid heartbeat token:

```text
403 Forbidden
```

## Safe redirect target handling

The gem must never send a consumed CAS ticket back as part of the CAS service URL.

Bad:

```text
/admin?ticket=ST-123
```

Good:

```text
/admin
```

The concern strips the `ticket` query param before building a CAS redirect target.

The safe redirect target priority is:

```text
1. Same-origin Referer, if present and valid
2. Current request URL
3. Configured service URL
4. Application base URL
```

Before returning the URL, the gem removes:

```text
ticket
```

This prevents CAS ticket reuse loops.

## Clearing session state

When the gem clears CAS session state, it removes the configured keys:

```ruby
session.delete(config.cas_user_key)
session.delete(:cas_authenticated_at)
session.delete(config.cas_ticket_key)
session.delete(config.cas_service_url_key)
session.delete(config.keep_alive_token_key)
```

`clear!` may return the last deleted value if written as sequential `session.delete` calls. That return value does not mean the session was not cleared.


## Heartbeat and session-expired modal

`CasinoClientSessionGuard` checks the CAS session in the background. If the session is no longer valid, it displays a countdown modal and redirects the user.

The host application needs to render:

1. Heartbeat meta tags.
2. The session redirect modal.

### 1. Configure the modal

Configure the modal text, countdown duration, and icon in the host application:

```ruby name=config/initializers/cas_session_guard.rb
CasinoClientSessionGuard.configure do |config|
  config.modal_title = "Session expired"
  config.modal_message = "Your CAS session is no longer active."
  config.modal_detail = "For security, you will be redirected to sign in again."
  config.modal_countdown_seconds = 10
  config.modal_redirecting_text = "Redirecting in seconds"

  config.modal_icon = lambda do |view|
    if view.respond_to?(:tabler_icon)
      view.tabler_icon(
        "alert-triangle",
        class: "icon icon-lg text-warning mb-2",
        aria: { hidden: true }
      )
    else
      view.content_tag(
        :span,
        "⚠",
        class: "cas-session-redirect-modal__icon text-warning mb-2",
        aria: { hidden: true }
      )
    end
  end
end
```

The icon callback receives the current Rails view as `view`. This allows the application to use its own view helpers, such as `tabler_icon`.

If `modal_icon` is not configured, the gem displays a default warning icon.

### 2. Render the heartbeat meta tags

Add the following helper inside the `<head>` element of the application layout:

```slim name=app/views/layouts/application.html.slim
head
  = cas_session_guard_meta_tags
```

The helper renders these three meta tags:

```slim name=app/views/layouts/application.html.slim
meta name="cas-session-guard-token" content=session[:keep_alive_token].to_s
meta name="cas-session-guard-heartbeat-url" content=CasinoClientSessionGuard.configuration.heartbeat_path
meta name="cas-session-guard-heartbeat-interval" content=(CasinoClientSessionGuard.configuration.heartbeat_interval.to_i * 1000)
```

They provide the following information to the gem's JavaScript:

| Meta tag | Purpose |
|---|---|
| `cas-session-guard-token` | Identifies the current browser session when sending a heartbeat. |
| `cas-session-guard-heartbeat-url` | Specifies the URL called by the heartbeat. |
| `cas-session-guard-heartbeat-interval` | Specifies how often the heartbeat runs, in milliseconds. |

For example, the generated HTML may look like:

```html
<meta name="cas-session-guard-token" content="abc123">
<meta name="cas-session-guard-heartbeat-url" content="/cas_session_guard/heartbeat">
<meta name="cas-session-guard-heartbeat-interval" content="60000">
```

The application should use the helper instead of writing these tags manually. This keeps the values synchronized with `CasinoClientSessionGuard.configure`.

### 3. Render the session redirect modal

Render the gem's modal inside the `<body>` element:

```slim name=app/views/layouts/application.html.slim
body
  = render_cas_session_redirect_modal
  = yield
```

The modal uses the values configured in `config/initializers/cas_session_guard.rb`.

For example:

```text
Session expired

Your CAS session is no longer active.
For security, you will be redirected to sign in again.

10

Redirecting in seconds
```

The modal is initially hidden. The gem's JavaScript displays it when the heartbeat determines that the CAS session is no longer valid.

### Complete layout example

A simple application layout looks like this:

```slim name=app/views/layouts/application.html.slim
doctype html
html
  head
    title My application

    = csrf_meta_tags
    = csp_meta_tag
    = cas_session_guard_meta_tags

  body
    = render_cas_session_redirect_modal
    = yield
```

### JavaScript setup

Import the heartbeat JavaScript from the application entrypoint:

```javascript name=app/javascript/application.js
import "cas_session_guard/heartbeat";
```

The heartbeat JavaScript reads the values generated by `cas_session_guard_meta_tags`.

It uses:

```javascript name=app/javascript/cas_session_guard/heartbeat.js
const token = document.querySelector(
  'meta[name="cas-session-guard-token"]'
)?.content;

const heartbeatUrl = document.querySelector(
  'meta[name="cas-session-guard-heartbeat-url"]'
)?.content;

const heartbeatInterval = Number.parseInt(
  document.querySelector(
    'meta[name="cas-session-guard-heartbeat-interval"]'
  )?.content,
  10
);
```

When the heartbeat response reports an expired session, the JavaScript finds:

```html
<div id="session-redirect-modal">
```

and displays the configured modal.

### How the complete flow works

```text
The Rails layout renders the heartbeat meta tags
  ↓
The Rails layout renders the hidden modal
  ↓
The gem's JavaScript reads the heartbeat configuration
  ↓
JavaScript checks the session at the configured interval
  ↓
The server reports that the CAS session has expired
  ↓
JavaScript displays the modal
  ↓
The configured countdown starts
  ↓
The browser redirects the user
```

### Important

Both helpers must be present in the layout:

```slim name=app/views/layouts/application.html.slim
= cas_session_guard_meta_tags
= render_cas_session_redirect_modal
```

If the meta tags are missing, the JavaScript cannot determine the heartbeat URL, token, or interval.

If the modal is missing, the JavaScript redirects immediately instead of showing the countdown.

## Common errors

### `undefined local variable or method cas_session_guard`

This happens if the layout uses:

```slim
meta name="cas-session-guard-heartbeat-url" content=cas_session_guard.heartbeat_path
```

but the engine route proxy is not available.

Use the configured path instead:

```slim
meta name="cas-session-guard-heartbeat-url" content=CasinoClientSessionGuard.configuration.heartbeat_path
```

### `/cas_session_guard/heartbeat` goes to `handle_invalid_locale`

This means the engine is not mounted at `/cas_session_guard`, or your app has a locale/catch-all route that captures the request.

If the heartbeat is admin-only, mount inside admin routes:

```ruby
namespace :admin do
  mount CasinoClientSessionGuard::Engine => "/cas_session_guard", as: "cas_session_guard"
end
```

Then configure:

```ruby
config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
```

### Repeated CAS redirects with `?ticket=...`

This usually means the CAS service URL includes an already-consumed ticket:

```text
/admin?ticket=ST-123
```

The service URL must remove the `ticket` query param before redirecting to CAS.


## Development

Run specs:

```bash
bundle exec rspec
```

## Security notes

- The heartbeat token is not a CAS ticket.
- The heartbeat token should be random and stored in the Rails session.
- The CAS ticket should not be exposed to JavaScript.
- The remote validator must return `false` on network errors unless the application intentionally chooses a fail-open policy.
- The gem removes consumed `ticket` params from redirect service URLs to avoid CAS ticket reuse loops.
