# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::Validators::CasinoSessionValidator do
  let(:service_url) { "https://app.example.com/admin" }
  let(:ticket) { "ST-123" }

  subject(:validator) do
    described_class.new(cas_service_url: service_url, cas_ticket: ticket)
  end

  before do
    configure_cas_session_guard
  end

  after do
    CasinoClientSessionGuard.reset_configuration!
  end

  describe "#valid?" do
    it "returns true when the remote validator says the ticket is valid" do
      stub_request(:get, "https://casino.example.com/api/v1/validate_ticket")
        .with(
          query: {
            "cas_service_url" => service_url,
            "cas_ticket" => ticket
          },
          headers: {
            "Authorization" => "Bearer token-123",
            "Accept" => "application/json"
          }
        )
        .to_return(
          status: 200,
          body: { valid: true }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect(validator.valid?).to be(true)
    end

    it "returns false when the API returns valid: false" do
      stub_request(:get, "https://casino.example.com/api/v1/validate_ticket")
        .to_return(
          status: 200,
          body: { valid: false }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect(validator.valid?).to be(false)
    end

    it "returns false when the API is unavailable" do
      stub_request(:get, "https://casino.example.com/api/v1/validate_ticket")
        .to_raise(SocketError)

      expect(validator.valid?).to be(false)
    end

    it "returns false when the base URL or token is blank" do
      CasinoClientSessionGuard.configuration.casino_base_url = nil
      CasinoClientSessionGuard.configuration.casino_api_token = nil

      expect(validator.valid?).to be(false)
    end
  end
end
