# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::HeartbeatsController, type: :controller do
  routes { CasinoClientSessionGuard::Engine.routes }

  before do
    CasinoClientSessionGuard.configure do |config|
      config.cas_user_key = :cas_user
      config.cas_ticket_key = :cas_last_valid_ticket
      config.cas_service_url_key = :cas_service_url
      config.keep_alive_token_key = :keep_alive_token

      config.session_validation = 5.minutes
      config.validation_buffer = 75.seconds
      config.heartbeat_interval = 60.seconds
      config.heartbeat_path = "/admin/cas_session_guard/heartbeat"

      # Required configuration
      config.casino_base_url = "https://casino.example.com"
      config.casino_api_token = "test-token"
      config.casino_validation_api_endpoint = "/api/v1/validate_ticket"
      config.modal_icon = "⚠"

      config.session_validator = ->(cas_service_url:, cas_ticket:) do
        cas_service_url.present? && cas_ticket.present?
      end

      config.reauthentication_url = lambda do |controller|
        "https://cas.example.com/login?service=https%3A%2F%2Fapp.example.com%2Fadmin"
      end
    end

    controller.session[:cas_user] = "admin@example.com"
    controller.session[:cas_service_url] = "https://app.example.com/admin"
    controller.session[:cas_last_valid_ticket] = "ST-123"
    controller.session[:keep_alive_token] = "abc123"
    request.headers["X-Keep-Alive-Token"] = "abc123"
  end

  after do
    CasinoClientSessionGuard.reset_configuration!
  end

  describe "GET #show" do
    it "returns 200 and ok: true when the session is valid" do
      get :show

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("ok" => true)
    end

    it "updates cas_authenticated_at to now + validation_buffer on successful validation" do
      allow(Time).to receive(:current).and_return(Time.utc(2026, 9, 19, 12, 0, 0))

      get :show

      expect(controller.session[:cas_authenticated_at]).to eq(Time.utc(2026, 9, 19, 12, 1, 15))
    end

    it "returns 403 when the heartbeat token is missing" do
      request.headers["X-Keep-Alive-Token"] = ""

      get :show

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 when the heartbeat token does not match the session token" do
      request.headers["X-Keep-Alive-Token"] = "wrong-token"

      get :show

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 when cas_user is missing" do
      controller.session[:cas_user] = nil

      get :show

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["reason"]).to eq("not_authenticated")
    end

    it "clears the session and returns 401 when remote validation fails" do
      CasinoClientSessionGuard.configuration.session_validator = ->(**_args) { false }

      get :show

      expect(response).to have_http_status(:unauthorized)
      expect(controller.session[:cas_user]).to be_nil
      expect(controller.session[:cas_authenticated_at]).to be_nil
      expect(JSON.parse(response.body)["reason"]).to eq("remote_session_invalid")
    end

    it "returns the configured redirect URL in the JSON body" do
      CasinoClientSessionGuard.configuration.session_validator = ->(**_args) { false }

      get :show

      body = JSON.parse(response.body)
      expect(body["redirect_url"]).to eq(
        "https://cas.example.com/login?service=https%3A%2F%2Fapp.example.com%2Fadmin"
      )
    end
  end
end
