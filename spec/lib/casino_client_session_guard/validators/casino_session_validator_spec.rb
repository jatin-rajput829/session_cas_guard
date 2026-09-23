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
      allow(validator.class).to receive(:get).and_return(
        double(
          success?: true,
          parsed_response: { "valid" => true }
        )
      )

      expect(validator.valid?).to be(true)
    end

    it "returns false when the API returns valid: false" do
      allow(validator.class).to receive(:get).and_return(
        double(
          success?: true,
          parsed_response: { "valid" => false }
        )
      )

      expect(validator.valid?).to be(false)
    end

    it "returns false when the API is unavailable" do
      allow(validator.class).to receive(:get).and_raise(SocketError, "Network error")

      expect(validator.valid?).to be(false)
    end

    it "returns false when the base URL or token is blank" do
      CasinoClientSessionGuard.configuration.casino_base_url = nil
      CasinoClientSessionGuard.configuration.casino_api_token = nil

      expect(validator.valid?).to be(false)
    end
  end
end
