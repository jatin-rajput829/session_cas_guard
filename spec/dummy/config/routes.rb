# frozen_string_literal: true

Dummy::Application.routes.draw do
  mount CasinoClientSessionGuard::Engine => "/cas_session_guard"
end
