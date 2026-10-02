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
  end

  describe ".configure!" do
    it "configures the CAS filter from gem configuration" do
      expect(CASClient::Frameworks::Rails::Filter).to receive(:configure).with(
        hash_including(
          cas_base_url: "https://cas.example.com",
          login_url: "https://cas.example.com/login",
          encode_extra_attributes_as: :json
        )
      )

      described_class.configure!
    end
  end

  describe ".login_url_for" do
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

  describe ".logout" do
    it "falls back to allow_other_host redirects when the upstream filter raises" do
      allow(described_class).to receive(:configure!).and_return(true)
      allow(CASClient::Frameworks::Rails::Filter).to receive(:logout).and_raise(StandardError)
      client = instance_double("CASClient client", logout_url: "https://cas.example.com/logout?destination=https%3A%2F%2Fapp.example.com%2Fadmin&gateway=true")
      allow(CASClient::Frameworks::Rails::Filter).to receive(:client).and_return(client)
      request.env["HTTP_REFERER"] = "https://app.example.com/admin"
      expect(controller).to receive(:redirect_to).with(
        "https://cas.example.com/logout?destination=https%3A%2F%2Fapp.example.com%2Fadmin&gateway=true",
        allow_other_host: true
      )

      described_class.logout(controller)
    end
  end
end