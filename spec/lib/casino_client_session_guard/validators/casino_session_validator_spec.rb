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
    it "returns a structured valid result when the remote validator says the ticket is valid" do
      allow(validator.class).to receive(:get).and_return(
        double(
          success?: true,
          parsed_response: { "valid" => true }
        )
      )

      expect(validator.validation_result).to include(
        status: :valid,
        reason: "valid"
      )
    end

    it "returns true when the remote validator says the ticket is valid" do
      allow(validator.class).to receive(:get).and_return(
        double(
          success?: true,
          parsed_response: { "valid" => true }
        )
      )

      events = capture_notifications("validator") { expect(validator.valid?).to be(true) }

      expect(events.last.payload).to include(
        valid: true,
        status: :valid,
        reason: "valid",
        http_success: true,
        ticket_present: true,
        service_url_present: true
      )
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

      events = capture_notifications("validator") { expect(validator.valid?).to be(false) }

      expect(events.last.payload).to include(
        valid: false,
        status: :error,
        reason: "network_error",
        error_class: "SocketError"
      )
    end

    it "returns a structured error result when the API is unavailable" do
      allow(validator.class).to receive(:get).and_raise(SocketError, "Network error")

      expect(validator.validation_result).to include(
        status: :error,
        reason: "network_error",
        error_class: "SocketError"
      )
    end

    it "returns false when the base URL or token is blank" do
      CasinoClientSessionGuard.configuration.casino_base_url = nil
      CasinoClientSessionGuard.configuration.casino_api_token = nil

      expect(validator.valid?).to be(false)
    end
  end
end
