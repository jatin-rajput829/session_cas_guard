# frozen_string_literal: true

module CasinoClientSessionGuard
  module Observability
    module_function

    def instrument(event_name, payload = {})
      ActiveSupport::Notifications.instrument(
        notification_name(event_name),
        payload
      )
    end

    def notification_name(event_name)
      "#{event_name}.casino_client_session_guard"
    end
  end
end
