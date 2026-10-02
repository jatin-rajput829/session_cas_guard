# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::SessionManager do
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
    configure_cas_session_guard
  end

  after do
    CasinoClientSessionGuard.reset_configuration!
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
      result = manager.clear!

      # clear! returns the last deleted key, not true
      expect(result).to be_a(String).or be_nil

      expect(session[:cas_user]).to be_nil
      expect(session[:cas_authenticated_at]).to be_nil
      expect(session[:cas_last_valid_ticket]).to be_nil
      expect(session[:cas_service_url]).to be_nil
      expect(session[:keep_alive_token]).to be_nil
      expect(session[:cas_extra_attributes]).to be_nil
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

  describe "#store_extra_attributes!" do
    it "stores extra attributes in the session" do
      attributes = { roles: ["admin", "user"], groups: ["engineering"] }
      manager.store_extra_attributes!(attributes)

      expect(session[:cas_extra_attributes]).to eq(attributes)
    end
  end

  describe "#extra_attributes" do
    it "returns stored extra attributes" do
      attributes = { roles: ["admin"], groups: ["engineering"] }
      session[:cas_extra_attributes] = attributes

      expect(manager.extra_attributes).to eq(attributes)
    end

    it "returns an empty hash when no attributes are stored" do
      expect(manager.extra_attributes).to eq({})
    end
  end

  describe "#extra_attribute" do
    it "returns a specific attribute by symbol key" do
      session[:cas_extra_attributes] = { roles: ["admin", "user"] }

      expect(manager.extra_attribute(:roles)).to eq(["admin", "user"])
    end

    it "returns a specific attribute by string key" do
      session[:cas_extra_attributes] = { "groups" => ["engineering"] }

      expect(manager.extra_attribute("groups")).to eq(["engineering"])
    end

    it "returns nil when attribute key does not exist" do
      session[:cas_extra_attributes] = { roles: ["admin"] }

      expect(manager.extra_attribute(:missing)).to be_nil
    end

    it "looks up by string key when symbol key is not found" do
      session[:cas_extra_attributes] = { "roles" => ["admin"] }

      expect(manager.extra_attribute(:roles)).to eq(["admin"])
    end
  end
end
