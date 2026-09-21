# frozen_string_literal: true

module CasSessionGuard
  class Engine < ::Rails::Engine
    isolate_namespace CasSessionGuard

    initializer "cas_session_guard.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper CasSessionGuard::ApplicationHelper
      end
    end

    # initializer "cas_session_guard.autoload" do
    #   ActiveSupport.on_load(:action_controller) do
    #     require "cas_session_guard/session_manager"
    #   end
    # end

    engine_name "cas_session_guard"
  end
end
