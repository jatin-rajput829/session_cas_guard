# frozen_string_literal: true

require "rails_helper"

RSpec.describe CasinoClientSessionGuard::ApplicationHelper, type: :helper do
  before do
    configure_cas_session_guard
    allow(helper).to receive(:session).and_return(
      {
        CasinoClientSessionGuard.configuration.keep_alive_token_key => "token-123"
      }
    )
  end

  after do
    CasinoClientSessionGuard.reset_configuration!
  end

  describe "#cas_session_guard_meta_tags" do
    it "renders heartbeat configuration meta tags when heartbeat is enabled" do
      html = helper.cas_session_guard_meta_tags

      expect(html).to include('name="cas-session-guard-token"')
      expect(html).to include('name="cas-session-guard-heartbeat-url"')
      expect(html).to include('name="cas-session-guard-heartbeat-interval"')
      expect(html).to include('name="cas-session-guard-storage-key"')
    end

    it "returns an empty string when heartbeat is disabled" do
      CasinoClientSessionGuard.configuration.heartbeat_enabled = false

      expect(helper.cas_session_guard_meta_tags).to eq("")
    end
  end

  describe "#render_cas_session_guard_javascript" do
    it "renders the inline heartbeat controller when heartbeat is enabled" do
      html = helper.render_cas_session_guard_javascript

      expect(html).to include("window.CasinoClientSessionGuardHeartbeat")
      expect(html).to include("showSessionRedirectModal")
    end

    it "returns an empty string when heartbeat is disabled" do
      CasinoClientSessionGuard.configuration.heartbeat_enabled = false

      expect(helper.render_cas_session_guard_javascript).to eq("")
    end
  end
end