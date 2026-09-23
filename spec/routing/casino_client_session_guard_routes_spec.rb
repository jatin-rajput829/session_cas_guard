# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CasinoClientSessionGuard routes", type: :routing do
  routes { CasinoClientSessionGuard::Engine.routes }

  it "routes /heartbeat to the heartbeat controller" do
    expect(get: "/heartbeat").to route_to(
      controller: "casino_client_session_guard/heartbeats",
      action: "show"
    )
  end
end
