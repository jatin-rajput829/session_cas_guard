# frozen_string_literal: true

CasinoClientSessionGuard::Engine.routes.draw do
  get "heartbeat", to: "heartbeats#show", as: :heartbeat
end
