# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::Configuration do
  subject(:config) { described_class.new }

  describe "defaults" do
    it "uses the default 5-minute validation window" do
      expect(config.session_validation).to eq(5.minutes)
    end

    it "uses the default 75-second validation buffer" do
      expect(config.validation_buffer).to eq(75.seconds)
    end

    it "uses the default 60-second heartbeat interval" do
      expect(config.heartbeat_interval).to eq(60.seconds)
    end

    it "uses the default gem heartbeat path" do
      expect(config.heartbeat_path).to eq("/cas_session_guard/heartbeat")
    end

    it "enables single logout by default" do
      expect(config.single_logout_enabled).to be(true)
    end

    it "uses fail_closed for remote validation failures by default" do
      expect(config.remote_validation_failure_policy).to eq(:fail_closed)
    end

    it "uses default CAS session keys" do
      expect(config.cas_user_key).to eq(:cas_user)
      expect(config.cas_ticket_key).to eq(:cas_last_valid_ticket)
      expect(config.cas_service_url_key).to eq(:cas_last_valid_ticket_service)
      expect(config.keep_alive_token_key).to eq(:keep_alive_token)
    end
  end

  describe "overrides" do
    it "allows runtime configuration overrides" do
      config.session_validation = 2.minutes
      config.validation_buffer = 90.seconds
      config.heartbeat_interval = 30.seconds
      config.heartbeat_path = "/admin/cas_session_guard/heartbeat"
      config.single_logout_enabled = false
      config.remote_validation_failure_policy = :fail_open

      expect(config.session_validation).to eq(2.minutes)
      expect(config.validation_buffer).to eq(90.seconds)
      expect(config.heartbeat_interval).to eq(30.seconds)
      expect(config.heartbeat_path).to eq("/admin/cas_session_guard/heartbeat")
      expect(config.single_logout_enabled).to be(false)
      expect(config.remote_validation_failure_policy).to eq(:fail_open)
    end
  end

  describe "validation" do
    it "rejects unsupported remote validation failure policies" do
      config.remote_validation_failure_policy = :unknown

      expect { config.validate! }.to raise_error(
        CasinoClientSessionGuard::ConfigurationError,
        /remote_validation_failure_policy/
      )
    end
  end
end
