# frozen_string_literal: true

module CasinoClientSessionGuard
  class ConfigurationError < StandardError; end

  # Configuration class stores all settings for CasinoClientSessionGuard.
  # These settings control how sessions are validated, heartbeats work, and modals are displayed.
  class Configuration
    # These policies decide what to do when CAS validation could not complete.
    # `fail_closed` is the strict option: treat the session as invalid.
    # `fail_open` is the tolerant option: keep the local session until a later check succeeds or fails definitively.
    REMOTE_VALIDATION_FAILURE_POLICIES = %i[fail_closed fail_open].freeze

    # List of settings that must be configured before the gem can work properly.
    REQUIRED_ATTRIBUTES = %i[
      heartbeat_path
      casino_base_url
      casino_api_token
      casino_validation_api_endpoint
      modal_icon
    ].freeze

    # Session validation settings - how often to check if session is still valid
    attr_accessor :session_validation,
                  :validation_buffer,
                  :heartbeat_enabled,
                  :heartbeat_interval,
                  :heartbeat_path,

                  # Session key names - customize where session data is stored
                  :cas_user_key,
                  :cas_ticket_key,
                  :cas_service_url_key,
                  :keep_alive_token_key,

                  # Custom validation logic - override how sessions are validated
                  :session_validator,
                  :remote_validation_failure_policy,
                  :reauthentication_url,

                  # CASINO server setup - CAS provider configuration
                  :casino_base_url,
                  :casino_api_token,
                  :casino_validation_api_endpoint,

                  # Sign-Out handling - how to track logged-out sessions
                  :single_logout_enabled,
                  :sign_out_store,
                  :sign_out_ttl,

                  # Modal UI settings - customize the expiration warning modal
                  :modal_title,
                  :modal_message,
                  :modal_detail,
                  :modal_countdown_seconds,
                  :modal_redirecting_text,
                  :modal_icon

    def initialize
      # How often the session must be re-validated with CAS (default: 5 minutes)
      @session_validation = 5.minutes

      # Add extra time to avoid edge-case race conditions (default: 75 seconds)
      @validation_buffer = 75.seconds

      # Browser heartbeat polling is enabled by default. Applications can disable it
      # when they want to keep only the server-side CAS protection flow.
      @heartbeat_enabled = true

      # Browser heartbeat interval to check session status (default: 60 seconds)
      @heartbeat_interval = 60.seconds

      # Endpoint path where heartbeat requests are sent (default: /cas_session_guard/heartbeat)
      @heartbeat_path = "/cas_session_guard/heartbeat"

      # Session storage keys - customize if you have conflicts with other gems
      @cas_user_key = :cas_user
      @cas_ticket_key = :cas_last_valid_ticket
      @cas_service_url_key = :cas_last_valid_ticket_service # by default key is from cas-client
      @keep_alive_token_key = :keep_alive_token

      # Custom validation - use your own logic to validate CAS tickets
      @session_validator = nil
      # Preserve the gem's existing behavior by default: if CAS validation cannot complete,
      # reject the local session unless the host app explicitly opts into fail-open handling.
      @remote_validation_failure_policy = :fail_closed
      @reauthentication_url = nil

      # CAS provider details - must be configured
      @casino_base_url = nil
      @casino_api_token = nil
      @casino_validation_api_endpoint = nil

      # Track which CAS tickets have been logged out (default: Rails cache)
      @single_logout_enabled = true
      @sign_out_store = CasinoClientSessionGuard::TicketStores::RailsCacheStore.new
      @sign_out_ttl = 12.hours

      # Default modal messages shown when session expires
      @modal_title = "Please wait"
      @modal_message = "Your session has expired."
      @modal_detail = "You will be redirected to sign in again."
      @modal_countdown_seconds = 10
      @modal_redirecting_text = "Redirecting in seconds"
      @modal_icon = nil

      # Default validator - calls CAS provider to check if ticket is still valid
      # It returns structured results so the heartbeat controller can distinguish
      # a definite invalid ticket from a temporary transport or server failure.
      @session_validator = lambda do |cas_service_url:, cas_ticket:|
        CasinoClientSessionGuard::Validators::CasinoSessionValidator.new(
          cas_service_url: cas_service_url,
          cas_ticket: cas_ticket
        ).validation_result
      end
    end

    # Checks if all required settings are configured.
    # Raises ConfigurationError if any required setting is missing.
    def validate!
      validate_remote_validation_failure_policy!

      missing_keys = REQUIRED_ATTRIBUTES.select do |attr|
        public_send(attr).blank?
      end

      return if missing_keys.empty?

      raise ConfigurationError,
            "CasinoClientSessionGuard configuration error: #{missing_keys.join(', ')} cannot be blank"
    end

    private

    def validate_remote_validation_failure_policy!
      return if REMOTE_VALIDATION_FAILURE_POLICIES.include?(remote_validation_failure_policy)

      raise ConfigurationError,
            "CasinoClientSessionGuard configuration error: remote_validation_failure_policy " \
            "must be one of #{REMOTE_VALIDATION_FAILURE_POLICIES.join(', ')}"
    end
  end
end
