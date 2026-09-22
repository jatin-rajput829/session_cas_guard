Dummy::Application.routes.draw do
  mount CasinoClientSessionGuard::Engine => "/cas_session_guard"
end
