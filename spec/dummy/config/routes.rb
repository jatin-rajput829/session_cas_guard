Dummy::Application.routes.draw do
  mount CasSessionGuard::Engine => "/cas_session_guard"
end
