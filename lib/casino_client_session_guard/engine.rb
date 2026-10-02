# frozen_string_literal: true

module CasinoClientSessionGuard
  class Engine < ::Rails::Engine
    isolate_namespace CasinoClientSessionGuard

    initializer "cas_session_guard.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper CasinoClientSessionGuard::ApplicationHelper
      end
    end

    initializer "cas_session_guard.single_logout_middleware" do |app|
      app.middleware.use CasinoClientSessionGuard::SingleLogoutMiddleware
    end

    config.after_initialize do
      CasinoClientSessionGuard::CasClient.configure!
    end

    # initializer "cas_session_guard.autoload" do
    #   ActiveSupport.on_load(:action_controller) do
    #     require "cas_session_guard/session_manager"
    #   end
    # end

    engine_name "cas_session_guard"
  end
end
