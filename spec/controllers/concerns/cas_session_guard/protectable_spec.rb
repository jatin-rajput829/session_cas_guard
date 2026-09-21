# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasSessionGuard::Protectable, type: :controller do
  controller(ActionController::Base) do
    include CasSessionGuard::Protectable

    def index
      head :ok
    end
  end

  before do
    configure_cas_session_guard
  end

  after do
    CasSessionGuard.reset_configuration!
  end

  describe "#enforce_cas_session" do
    it "returns 401 for Turbo/XHR requests when the user is missing" do
      request.headers["X-Requested-With"] = "XMLHttpRequest"

      get :index

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["X-Session-Expired"]).to eq("true")
    end

    it "strips the ticket param from the redirect target" do
      request.env["HTTP_HOST"] = "app.example.com"
      request.env["ORIGINAL_FULLPATH"] = "/admin?ticket=ST-123&tab=profile"

      allow(controller).to receive(:turbo_or_xhr_request?).and_return(true)

      get :index

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["Turbo-Visit-Location"]).not_to include("ticket=ST-123")
    end

    it "calls CAS filter for full-page requests when the user is missing" do
      allow(controller).to receive(:turbo_or_xhr_request?).and_return(false)
      allow(CASClient::Frameworks::Rails::Filter).to receive(:filter).and_return(true)

      get :index

      expect(CASClient::Frameworks::Rails::Filter).to have_received(:filter)
    end

    it "returns early when the session is already authenticated and valid" do
      session[:cas_user] = "admin@example.com"
      session[:cas_authenticated_at] = Time.current + 75.seconds

      get :index

      expect(response).to have_http_status(:ok)
    end

    it "clears the session and redirects when authentication is stale" do
      session[:cas_user] = "admin@example.com"
      session[:cas_authenticated_at] = 6.minutes.ago

      allow(controller).to receive(:turbo_or_xhr_request?).and_return(false)
      allow(CASClient::Frameworks::Rails::Filter).to receive(:filter).and_return(true)

      get :index

      expect(session[:cas_user]).to be_nil
      expect(session[:cas_authenticated_at]).to be_nil
    end
  end
end
