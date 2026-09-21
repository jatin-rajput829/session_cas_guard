# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CasSessionGuard routes", type: :routing do
  routes { CasSessionGuard::Engine.routes }

  it "routes /heartbeat to the heartbeat controller" do
    expect(get: "/heartbeat").to route_to(
      controller: "cas_session_guard/heartbeats",
      action: "show"
    )
  end
end
