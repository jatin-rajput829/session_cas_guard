# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::SingleLogoutsController, type: :controller do
  routes { CasinoClientSessionGuard::Engine.routes }

  before do
    configure_cas_session_guard
  end

  after do
    CasinoClientSessionGuard.reset_configuration!
  end

  describe "POST #create" do
    it "returns not_found when single logout is disabled" do
      CasinoClientSessionGuard.configuration.single_logout_enabled = false

      post :create, params: { ticket: "ST-123" }

      expect(response).to have_http_status(:not_found)
      expect(
        CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-123")
      ).to be(false)
    end

    it "invalidates the submitted ticket directly" do
      events = capture_notifications("single_logout") { post :create, params: { ticket: "ST-123" } }

      expect(response).to have_http_status(:ok)
      expect(
        CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-123")
      ).to be(true)
      expect(events.last.payload).to include(
        outcome: "processed",
        ticket_count: 1,
        source: "controller"
      )
    end

    it "invalidates the ticket from a CAS logoutRequest payload" do
      post :create, params: {
        logoutRequest: <<~XML
          <samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
            <samlp:SessionIndex>ST-456</samlp:SessionIndex>
          </samlp:LogoutRequest>
        XML
      }

      expect(response).to have_http_status(:ok)
      expect(
        CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-456")
      ).to be(true)
    end

    it "invalidates every session index from a CAS logoutRequest payload" do
      post :create, params: {
        logoutRequest: <<~XML
          <samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
            <samlp:SessionIndex>ST-456</samlp:SessionIndex>
            <samlp:SessionIndex>ST-789</samlp:SessionIndex>
          </samlp:LogoutRequest>
        XML
      }

      expect(response).to have_http_status(:ok)
      expect(
        CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-456")
      ).to be(true)
      expect(
        CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-789")
      ).to be(true)
    end

    it "invalidates the ticket from a raw XML body" do
      allow_any_instance_of(ActionDispatch::Request).to receive(:media_type).and_return("text/xml")
      allow_any_instance_of(ActionDispatch::Request).to receive(:raw_post).and_return(<<~XML)
        <samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
          <samlp:SessionIndex>ST-999</samlp:SessionIndex>
        </samlp:LogoutRequest>
      XML

      post :create

      expect(response).to have_http_status(:ok)
      expect(
        CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-999")
      ).to be(true)
    end

    it "returns bad_request when the payload does not include a ticket" do
      post :create, params: { logoutRequest: "<logout></logout>" }

      expect(response).to have_http_status(:bad_request)
    end
  end
end
