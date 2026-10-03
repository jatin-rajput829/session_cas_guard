
## Testing Login and Logout in a Client App

The best way to test this gem in a host Rails app is to exercise the same request flow that the app will use in production:

1. Configure the gem in the test initializer.
2. Stub the CAS validation URL the app calls after a login callback.
3. Simulate a request with a CAS `ticket` parameter.
4. Assert that the session contains the authenticated user and ticket.
5. Simulate logout by calling `perform_cas_logout` or `CasClient.logout` and assert the redirect target.

### Example: login flow spec

```ruby
# spec/requests/admin_auth_spec.rb
require "rails_helper"

RSpec.describe "Admin authentication", type: :request do
  before do
    CasinoClientSessionGuard.configure do |config|
      config.cas_base_url = "https://cas.example.com"
      config.cas_login_url = "https://cas.example.com/login"
      config.casino_base_url = "https://cas.example.com"
      config.casino_api_token = "test-token"
      config.casino_validation_api_endpoint = "/api/v1/validate_ticket"
      config.heartbeat_enabled = false
    end

    allow_any_instance_of(CasinoClientSessionGuard::CasClient::TicketValidator)
      .to receive(:call)
      .and_return(
        success: true,
        username: "admin@example.com",
        extra_attributes: { "role" => "admin" }
      )
  end

  it "authenticates a request that includes a valid CAS ticket" do
    get "/admin", params: { ticket: "ST-123" }

    expect(response).to have_http_status(:ok)
    expect(session[:cas_user]).to eq("admin@example.com")
    expect(session[:cas_last_valid_ticket]).to eq("ST-123")
    expect(session[:cas_extra_attributes]).to include("role")
  end
end
```

This follows the same pattern as the gem’s own CAS client specs: a request without a ticket redirects to the CAS login URL, while a request with a valid ticket stores session state and allows the protected action.

### Example: logout flow spec

```ruby
# spec/controllers/admin_controller_spec.rb
require "rails_helper"

RSpec.describe AdminController, type: :controller do
  before do
    CasinoClientSessionGuard.configure do |config|
      config.cas_base_url = "https://cas.example.com"
      config.cas_login_url = "https://cas.example.com/login"
      config.casino_base_url = "https://cas.example.com"
      config.casino_api_token = "test-token"
      config.casino_validation_api_endpoint = "/api/v1/validate_ticket"
      config.heartbeat_enabled = false
    end

    request.env["HTTP_HOST"] = "app.example.com"
    request.env["HTTPS"] = "on"
    session[:cas_user] = "admin@example.com"
    session[:cas_last_valid_ticket] = "ST-123"
    session[:cas_last_valid_ticket_service] = "https://app.example.com/admin"
  end

  it "clears the local session and redirects to CAS logout" do
    expect(controller).to receive(:redirect_to).with(
      "https://cas.example.com/logout?destination=https%3A%2F%2Fapp.example.com%2Fadmin&gateway=true",
      allow_other_host: true
    )

    controller.send(:perform_cas_logout, redirect_url: "https://app.example.com/admin")
  end
end
```

### Example: back-channel logout invalidation test

```ruby
it "invalidates the stored CAS ticket after logout" do
  session[:cas_user] = "admin@example.com"
  session[:cas_last_valid_ticket] = "ST-123"

  CasinoClientSessionGuard.configuration.sign_out_store.invalidate(
    ticket: "ST-123",
    ttl: 12.hours
  )

  expect(CasinoClientSessionGuard::SessionManager.new(session).ticket_invalidated?).to be(true)
end
```

### Required validation flow scenarios

These are the core client-app specs your app should keep passing to validate the full authentication lifecycle.

#### 1) Request without ticket redirects to CAS login

```ruby
it "redirects to CAS login when the request does not include a ticket" do
  get "/admin"

  expect(response).to have_http_status(:redirect)
  expect(response).to redirect_to(%r{https://cas.example.com/login\?service=})
end
```

#### 2) Valid ticket stores authenticated session

```ruby
it "stores an authenticated session when the CAS ticket is valid" do
  allow(CasinoClientSessionGuard::CasClient::TicketValidator).to receive(:new).and_return(
    double(call: { success: true, username: "admin@example.com", extra_attributes: { "role" => "admin" } })
  )

  get "/admin", params: { ticket: "ST-123" }

  expect(response).to have_http_status(:ok)
  expect(session[:cas_user]).to eq("admin@example.com")
  expect(session[:cas_last_valid_ticket]).to eq("ST-123")
  expect(session[:cas_last_valid_ticket_service]).to include("/admin")
end
```

#### 3) Logout clears session and hits CAS logout URL

```ruby
it "clears the local session and redirects to CAS logout" do
  session[:cas_user] = "admin@example.com"
  session[:cas_last_valid_ticket] = "ST-123"
  session[:cas_last_valid_ticket_service] = "https://app.example.com/admin"

  expect(controller).to receive(:redirect_to).with(
    "https://cas.example.com/logout?destination=https%3A%2F%2Fapp.example.com%2Fadmin&gateway=true",
    allow_other_host: true
  )

  controller.send(:perform_cas_logout, redirect_url: "https://app.example.com/admin")

  expect(session[:cas_user]).to be_nil
  expect(session[:cas_last_valid_ticket]).to be_nil
end
```

### Recommended assertions

When writing client-app tests, assert at least these items:

- the protected action redirects to the CAS login when no ticket is present
- the request with a valid CAS `ticket` creates a logged-in session
- the session contains `:cas_user`, `:cas_last_valid_ticket`, and `:cas_last_valid_ticket_service`
- the logout redirect points to the CAS logout URL and includes the same-origin `destination`
- an external or malicious `referer` does not get passed through as the CAS `destination`
- a ticket marked invalid by the sign-out store causes the session to be rejected
