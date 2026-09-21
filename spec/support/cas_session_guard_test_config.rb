# frozen_string_literal: true

module CasSessionGuardTestConfig
  DEFAULT_REAUTHENTICATION_URL =
    "https://cas.example.com/login?service=https%3A%2F%2Fapp.example.com%2Fadmin"

  def configure_cas_session_guard(
    cas_user_key: :cas_user,
    cas_ticket_key: :cas_last_valid_ticket,
    cas_service_url_key: :cas_service_url,
    keep_alive_token_key: :keep_alive_token,
    session_validation: 5.minutes,
    validation_buffer: 75.seconds,
    heartbeat_interval: 60.seconds,
    heartbeat_path: "/admin/cas_session_guard/heartbeat",
    casino_base_url: "https://casino.example.com",
    casino_api_token: "test-token",
    casino_validation_api_endpoint: "/api/v1/validate_ticket",
    session_validator: nil,
    reauthentication_url: DEFAULT_REAUTHENTICATION_URL
  )
    CasSessionGuard.configure do |config|
      config.cas_user_key = cas_user_key
      config.cas_ticket_key = cas_ticket_key
      config.cas_service_url_key = cas_service_url_key
      config.keep_alive_token_key = keep_alive_token_key

      config.session_validation = session_validation
      config.validation_buffer = validation_buffer
      config.heartbeat_interval = heartbeat_interval
      config.heartbeat_path = heartbeat_path

      config.casino_base_url = casino_base_url
      config.casino_api_token = casino_api_token
      config.casino_validation_api_endpoint = casino_validation_api_endpoint

      config.session_validator =
        session_validator ||
        lambda do |cas_service_url:, cas_ticket:|
          cas_service_url.present? && cas_ticket.present?
        end

      config.reauthentication_url = lambda do |_controller|
        reauthentication_url
      end
    end
  end

  def reset_cas_session_guard_config!
    CasSessionGuard.reset_configuration!
  end
end

RSpec.configure do |config|
  config.include CasSessionGuardTestConfig

  config.after do
    CasSessionGuard.reset_configuration!
  end
end
