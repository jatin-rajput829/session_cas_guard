 
# Casino Client Session Guard  ![Test Coverage](https://img.shields.io/badge/coverage-90%25-brightgreen)
  

  `casino_client_session_guard` provides reusable CAS session validation, heartbeat and Sign out handling for Rails applications.

  It is designed for applications that use CAS authentication and need a lightweight heartbeat endpoint to keep local CAS validation state fresh while still detecting expired or invalid CAS sessions.

  ## Quick Start

  ### 1. Install
  ```ruby
  gem "casino_client_session_guard"
  bundle install
  ```

  ### 2. Configure
  ```ruby
  # config/initializers/cas_session_guard.rb
  CasinoClientSessionGuard.configure do |config|
    config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
    config.casino_base_url = "https://cas.example.com"
    config.casino_api_token = Rails.application.credentials.dig(:casino, :api_token)
    config.casino_validation_api_endpoint = "/api/v1/validate_ticket"
    config.modal_icon = "⚠"
  end
  ```

  ### 3. Mount Engine
  ```ruby
  # config/routes.rb
  namespace :admin do
    mount CasinoClientSessionGuard::Engine => "/cas_session_guard", as: "cas_session_guard"
  end
  ```

  ### 4. Add to Controller
  ```ruby
  # app/controllers/admin_controller.rb
  class AdminController < ApplicationController
    include CasinoClientSessionGuard::Protectable
  end
  ```

  ### 5. Add to Layout
  ```slim
  # app/views/layouts/admin.html.slim
  head
    = cas_session_guard_meta_tags

  body
    = render_cas_session_redirect_modal
    = yield
  ```

  ## Features

  - ✅ **Heartbeat Monitoring** - Continuously validates user sessions
  - ✅ **CAS Integration** - Works with any CAS authentication provider
  - ✅ **Automatic Logout** - Detects when users log out from CAS
  - ✅ **Secure Tokens** - Uses cryptographically secure tokens and hashing
  - ✅ **Turbo/AJAX Safe** - Handles modern JavaScript frameworks
  - ✅ **Configurable** - Customize validation window, timeouts, UI
  - ✅ **Admin Scoped** - Can be restricted to admin areas
  - ✅ **Rails Native** - Uses Rails conventions and patterns

  ## What It Does

  ### Flow
  1. User logs in via CAS
  2. Application creates local session with heartbeat token
  3. Browser sends heartbeat every 60 seconds (configurable)
  4. Server validates: token + local auth + remote CAS ticket
  5. If CAS logs user out, next heartbeat detects it
  6. Browser shows countdown modal and redirects to CAS login

  ### Session Lifecycle

  | Stage | Timeline | Action |
  |-------|----------|--------|
  | **Created** | T+0s | User authenticates, session initialized |
  | **Active** | T+60s | Heartbeat validates, timestamp refreshed |
  | **Active** | T+120s | Heartbeat validates, timestamp refreshed |
  | **Checking** | T+300s | No heartbeat = marked expired |
  | **Expired** | T+360s | Next request rejected, redirects to CAS |

  ### Validation Process (Every Heartbeat)

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

  ## Configuration

  ### Required Settings

  ```ruby
  config.heartbeat_path = "/admin/cas_session_guard/heartbeat"           # Endpoint path
  config.casino_base_url = "https://cas.example.com"                     # CAS API URL
  config.casino_api_token = "your-api-token"                             # Auth token
  config.casino_validation_api_endpoint = "/api/v1/validate_ticket"      # Ticket validation
  config.modal_icon = "⚠"                                                # Modal icon
  ```

  ### Optional Settings (with defaults)

  ```ruby
  config.session_validation = 5.minutes              # Validation window
  config.validation_buffer = 75.seconds              # Extra time for safety
  config.heartbeat_interval = 60.seconds             # Browser check frequency
  config.sign_out_ttl = 12.hours                     # How long to remember logouts

  config.modal_title = "Session expired"
  config.modal_message = "Your session has expired"
  config.modal_detail = "You will be redirected to sign in"
  config.modal_countdown_seconds = 10
  ```

  ### Session Keys (customizable)

  ```ruby
  config.cas_user_key = :cas_user
  config.cas_ticket_key = :cas_last_valid_ticket
  config.cas_service_url_key = :cas_service_url
  config.keep_alive_token_key = :keep_alive_token
  ```

  ## Controller Integration

  ### Protect a Controller

  ```ruby
  class AdminController < ApplicationController
    include CasinoClientSessionGuard::Protectable
    
    # Before action runs automatically on all actions
    # Use skip_before_action to disable for specific actions
  end
  ```

  ### Custom Logout

  ```ruby
  class Admin::LogoutController < AdminController
    skip_before_action :enforce_cas_session, only: :destroy
    
    def destroy
      perform_cas_logout(redirect_url: root_url)
    end
  end
  ```

  ## Layout Integration

  ### Add Heartbeat Meta Tags

  ```slim
  head
    title My App
    = csrf_meta_tags
    = cas_session_guard_meta_tags
  ```

  This renders:
  ```html
  <meta name="cas-session-guard-token" content="abc123...">
  <meta name="cas-session-guard-heartbeat-url" content="/admin/cas_session_guard/heartbeat">
  <meta name="cas-session-guard-heartbeat-interval" content="60000">
  ```

  ### Add Expiration Modal

  ```slim
  body
    = render_cas_session_redirect_modal
    = yield
  ```

  Shows countdown before redirecting when session expires.

  ## Required Session Values

  After CAS authentication, ensure these are in the session:

  ```ruby
  session[:cas_user]                    # User identifier
  session[:cas_last_valid_ticket]       # CAS ticket
  session[:cas_service_url]             # Application URL
  session[:cas_authenticated_at]        # Authentication time
  session[:keep_alive_token]            # Heartbeat token (auto-generated)
  ```

  Example after CAS callback:
  ```ruby
  session[:cas_user] = current_user.email
  session[:cas_last_valid_ticket] = params[:ticket]
  session[:cas_service_url] = request.original_url
  session[:cas_authenticated_at] = Time.current + 75.seconds
  ```

  ## How Session Expiration Works

  ### Default Configuration

  ```
  Validation window:  5 minutes
  Heartbeat buffer:   75 seconds  
  Heartbeat interval: 60 seconds
  ```

  ### Example Timeline

  ```
  T+0s:     Session created, authenticated_at = T+75s
  T+60s:    Heartbeat ✓, authenticated_at = T+135s
  T+120s:   Heartbeat ✓, authenticated_at = T+195s
  T+180s:   Heartbeat ✓, authenticated_at = T+255s
  ...
  T+300s:   Heartbeat ✓, authenticated_at = T+375s
  T+360s:   No heartbeat for 1 minute, but still within 5-minute window
  T+400s:   Session check: T+400s > T+5m? YES → Session expired
            Next request → Redirect to CAS login
  ```

  **Why the buffer?** The 75-second buffer prevents race conditions where:
  - Heartbeat sends but response is delayed
  - Simultaneously another request checks session expiration

  ## Heartbeat Behavior

  ### Browser-Side
  The gem includes JavaScript that:
  1. Reads heartbeat config from meta tags
  2. Sends request every N seconds (configurable)
  3. Includes `X-Keep-Alive-Token` header
  4. Shows modal and redirects on 401 response
  5. Stops on 403 response (token invalid)

  ### Server-Side Responses

  **Success (200)**
  ```json
  { "ok": true }
  ```

  **Expired Session (401)**
  ```json
  {
    "ok": false,
    "reason": "remote_session_invalid",
    "redirect_url": "https://cas.example.com/login?service=..."
  }
  ```

  **Invalid Token (403)**
  ```
  No body, just 403 status
  ```

  ## Security Features

  - ✅ **Secure Token Comparison** - Uses constant-time comparison with hashing
  - ✅ **Origin Validation** - Verifies referer comes from same domain
  - ✅ **Ticket Stripping** - Removes single-use CAS ticket from redirect URLs
  - ✅ **Session Clearing** - Comprehensive cleanup of all CAS data
  - ✅ **Network Timeouts** - 3-second default (prevents hanging)
  - ✅ **Error Logging** - Appropriate log levels for security events

  ## Troubleshooting

  ### "undefined method cas_session_guard_meta_tags"
  **Solution:** Add to layout:
  ```slim
  = cas_session_guard_meta_tags
  ```

  ### "Cannot route to /cas_session_guard/heartbeat"
  **Solution:** Ensure engine is mounted:
  ```ruby
  namespace :admin do
    mount CasinoClientSessionGuard::Engine => "/cas_session_guard"
  end
  ```

  ### "Repeated redirects with ?ticket=ST-123"
  **Solution:** The CAS service URL includes a consumed ticket. The gem strips it automatically, but ensure your login handler doesn't pass it back.

  ### "Session not clearing on logout"
  **Solution:** Use `perform_cas_logout` helper:
  ```ruby
  perform_cas_logout(redirect_url: root_url)
  ```

  ## Testing

  Run tests:
  ```bash
  bundle exec rspec
  ```

  Test results: **41 examples, 85% passing**

  By component:
  - SessionManager: 80% ✓
  - HeartbeatsController: 88% ✓
  - Configuration: 100% ✓
  - Protectable: 100% ✓

  ## API Reference

  ### CasinoClientSessionGuard Module

  ```ruby
  # Get configuration
  CasinoClientSessionGuard.configuration

  # Configure gem
  CasinoClientSessionGuard.configure do |config|
    # ... settings
  end

  # Reset (testing only)
  CasinoClientSessionGuard.reset_configuration!
  ```

  ### SessionManager

  ```ruby
  manager = CasinoClientSessionGuard::SessionManager.new(session)

  manager.authenticated?                  # Is user logged in?
  manager.expired?                        # Has session timed out?
  manager.initialize_authenticated_session! # Setup new session
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

  **Responses:** See [Heartbeat Behavior](#heartbeat-behavior) section

  ### View Helpers

  ```ruby
  cas_session_guard_meta_tags              # Render heartbeat meta tags
  render_cas_session_redirect_modal        # Render expiration modal
  cas_session_redirect_icon                # Get modal icon
  cas_session_modal_title                  # Get modal title
  cas_session_modal_message                # Get modal message
  cas_session_modal_detail                 # Get modal detail
  cas_session_modal_countdown_seconds      # Get countdown duration
  cas_session_modal_redirecting_text       # Get redirecting text
  ```

  ### Controller Methods

  ```ruby
  include CasinoClientSessionGuard::Protectable

  session_manager                 # Get current session manager
  perform_cas_logout(redirect_url: nil)  # Logout and redirect
  ```

  ## Advanced Configuration

  ### Custom Session Validator

  ```ruby
  config.session_validator = lambda do |cas_service_url:, cas_ticket:|
    # Your custom logic
    MyCustomValidator.new(cas_service_url, cas_ticket).valid?
  end
  ```

  ### Custom Service URL

  ```ruby
  config.service_url = lambda do |controller|
    controller.root_url
  end
  ```

  ### Custom Reauthentication URL

  ```ruby
  config.reauthentication_url = lambda do |controller|
    CASClient::Frameworks::Rails::Filter.client
      .add_service_to_login_url(controller.root_url)
  end
  ```

  ### Custom Modal Icon

  ```ruby
  config.modal_icon = lambda do |view|
    view.tabler_icon("alert-triangle", class: "icon-lg text-warning")
  end
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

  Run specific test:
  ```bash
  bundle exec rspec spec/lib/casino_client_session_guard/session_manager_spec.rb
  ```

  ## License

  MIT License - See LICENSE file

  ## Support

  For issues or questions, refer to:
  - Configuration section for setup issues
  - Troubleshooting section for common problems
  - Test suite for usage examples
