# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::CasClient, type: :controller do
  controller(ActionController::Base) do
    def index
      head :ok
    end
  end

  before do
    configure_cas_session_guard
    request.env["HTTP_HOST"] = "app.example.com"
    allow(controller.request).to receive(:original_url).and_return("https://app.example.com/admin")
  end

  describe ".configure!" do
    it "is a no-op that still returns true" do
      expect(described_class.configure!).to be(true)
    end
  end

  describe ".login_url_for" do
    it "builds a service-param CAS login URL" do
      expect(described_class.login_url_for("https://app.example.com/admin")).to eq(
        "https://cas.example.com/login?service=https%3A%2F%2Fapp.example.com%2Fadmin"
      )
    end

    it "raises when CAS redirect configuration is missing" do
      CasinoClientSessionGuard.configuration.cas_base_url = nil
      CasinoClientSessionGuard.configuration.cas_login_url = nil
      CasinoClientSessionGuard.configuration.casino_base_url = nil

      expect { described_class.login_url_for("https://app.example.com/admin") }.to raise_error(
        CasinoClientSessionGuard::ConfigurationError,
        /cas_base_url or cas_login_url/
      )
    end
  end

  describe ".filter" do
    it "redirects to CAS login when the request has no ticket" do
      expect(controller).to receive(:redirect_to).with(
        "https://cas.example.com/login?service=https%3A%2F%2Fapp.example.com%2Fadmin",
        allow_other_host: true
      )

      expect(described_class.filter(controller)).to be(false)
    end

    it "validates the CAS ticket and stores session details" do
      allow(controller.request).to receive(:original_url).and_return("https://app.example.com/admin?ticket=ST-123")
      allow(controller.params).to receive(:[]).with(:ticket).and_return("ST-123")
      allow(controller.params).to receive(:[]).with("ticket").and_call_original

      WebMock.stub_request(:get, "https://cas.example.com/proxyValidate")
        .with(query: { service: "https://app.example.com/admin", ticket: "ST-123" })
        .to_return(
          status: 200,
          body: <<~XML,
            <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
              <cas:authenticationSuccess>
                <cas:user>admin@example.com</cas:user>
                <cas:attributes>
                  <cas:role>admin</cas:role>
                </cas:attributes>
              </cas:authenticationSuccess>
            </cas:serviceResponse>
          XML
          headers: { "Content-Type" => "application/xml" }
        )

      expect(described_class.filter(controller)).to be(true)
      expect(session[:cas_user]).to eq("admin@example.com")
      expect(session[:cas_last_valid_ticket]).to eq("ST-123")
      expect(session[:cas_service_url]).to eq("https://app.example.com/admin")
      expect(session[:cas_extra_attributes]).to eq({ "role" => "admin" }.to_json)
    end
  end

  describe ".logout" do
    it "redirects to the CAS logout URL with destination" do
      request.env["HTTP_REFERER"] = "https://app.example.com/admin"
      expect(controller).to receive(:redirect_to).with(
        "https://cas.example.com/logout?destination=https%3A%2F%2Fapp.example.com%2Fadmin&gateway=true",
        allow_other_host: true
      )

      described_class.logout(controller)
    end
  end
end