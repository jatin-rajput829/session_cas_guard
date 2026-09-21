# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasSessionGuard::SessionManager do
  subject(:manager) { described_class.new(session) }

  let(:session) do
    {
      cas_user: "admin@example.com",
      cas_last_valid_ticket: "ST-123",
      cas_service_url: "https://app.example.com/admin",
      keep_alive_token: "token-123",
      cas_authenticated_at: Time.current + 75.seconds
    }
  end

  before do
    CasSessionGuard.configure do |config|
      config.cas_user_key = :cas_user
      config.cas_ticket_key = :cas_last_valid_ticket
      config.cas_service_url_key = :cas_service_url
      config.keep_alive_token_key = :keep_alive_token
      config.validation_buffer = 75.seconds
      config.session_validation = 5.minutes
    end
  end

  after do
    CasSessionGuard.reset_configuration!
  end

  describe "#expired?" do
    it "returns false for a fresh validation window" do
      expect(manager.expired?).to be(false)
    end

    it "returns true when the validation window is older than 5 minutes" do
      session[:cas_authenticated_at] = 6.minutes.ago

      expect(manager.expired?).to be(true)
    end

    it "returns false when no timestamp exists" do
      session.delete(:cas_authenticated_at)

      expect(manager.expired?).to be(false)
    end
  end

  describe "#authenticated?" do
    it "returns true when cas_user is present" do
      expect(manager.authenticated?).to be(true)
    end

    it "returns false when cas_user is blank" do
      session[:cas_user] = nil

      expect(manager.authenticated?).to be(false)
    end
  end

  describe "#mark_cas_session_validated!" do
    it "sets cas_authenticated_at to now + validation_buffer" do
      allow(Time).to receive(:current).and_return(Time.zone.parse("2026-09-19 12:00:00 UTC"))

      manager.mark_cas_session_validated!

      expect(session[:cas_authenticated_at]).to eq(Time.zone.parse("2026-09-19 12:01:15 UTC"))
    end
  end

  describe "#initialize_authenticated_session!" do
    it "initializes the timestamp and heartbeat token" do
      session.delete(:cas_authenticated_at)
      session.delete(:keep_alive_token)

      manager.initialize_authenticated_session!

      expect(session[:cas_authenticated_at]).to be_present
      expect(session[:keep_alive_token]).to be_present
    end
  end

  describe "#clear!" do
    it "removes all CAS-owned session keys and returns true" do
      expect(manager.clear!).to eq(true)

      expect(session[:cas_user]).to be_nil
      expect(session[:cas_authenticated_at]).to be_nil
      expect(session[:cas_last_valid_ticket]).to be_nil
      expect(session[:cas_service_url]).to be_nil
      expect(session[:keep_alive_token]).to be_nil
    end
  end

  describe "#heartbeat_token" do
    it "returns the current session token" do
      expect(manager.heartbeat_token).to eq("token-123")
    end
  end

  describe "#cas_ticket" do
    it "returns the current CAS ticket" do
      expect(manager.cas_ticket).to eq("ST-123")
    end
  end

  describe "#cas_service_url" do
    it "returns the current CAS service URL" do
      expect(manager.cas_service_url).to eq("https://app.example.com/admin")
    end
  end
end
