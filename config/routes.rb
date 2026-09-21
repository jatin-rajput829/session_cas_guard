# frozen_string_literal: true

CasSessionGuard::Engine.routes.draw do
  get "heartbeat", to: "heartbeats#show", as: :heartbeat
end
