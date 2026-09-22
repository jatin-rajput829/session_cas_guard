# frozen_string_literal: true

module CasinoClientSessionGuard
  class ConfigurationError < StandardError; end

  class Configuration
    REQUIRED_ATTRIBUTES = %i[
      heartbeat_path
      casino_base_url
      casino_api_token
      casino_validation_api_endpoint
      modal_icon
    ].freeze

    attr_accessor :session_validation,
                  :validation_buffer,
                  :heartbeat_interval,
                  :heartbeat_path,
                  :cas_user_key,
                  :cas_ticket_key,
                  :cas_service_url_key,
                  :keep_alive_token_key,
                  :session_validator,
                  :reauthentication_url,

                  # CASINO setup
                  :casino_base_url,
                  :casino_api_token,
                  :casino_validation_api_endpoint,

                  # Sign-Out
                  :sign_out_store,
                  :sign_out_ttl,

                  # Modal configuration
                  :modal_title,
                  :modal_message,
                  :modal_detail,
                  :modal_countdown_seconds,
                  :modal_redirecting_text,
                  :modal_icon

    def initialize
      @session_validation = 5.minutes
      @validation_buffer = 75.seconds
      @heartbeat_interval = 60.seconds
      @heartbeat_path = nil

      @cas_user_key = :cas_user
      @cas_ticket_key = :cas_last_valid_ticket
      @cas_service_url_key = :cas_last_valid_ticket_service
      @keep_alive_token_key = :keep_alive_token

      @session_validator = nil
      @reauthentication_url = nil

      @casino_base_url = nil
      @casino_api_token = nil
      @casino_validation_api_endpoint = nil

      @sign_out_store = CasinoClientSessionGuard::TicketStores::RailsCacheStore.new
      @sign_out_ttl = 12.hours

      @modal_title = "Please wait"
      @modal_message = "Your session has expired."
      @modal_detail = "You will be redirected to sign in again."
      @modal_countdown_seconds = 10
      @modal_redirecting_text = "Redirecting in seconds"
      @modal_icon = nil

      @session_validator = lambda do |cas_service_url:, cas_ticket:|
        CasinoClientSessionGuard::Validators::CasinoSessionValidator.new(
          cas_service_url: cas_service_url,
          cas_ticket: cas_ticket
        ).valid?
      end
    end

    def validate!
      missing_keys = REQUIRED_ATTRIBUTES.select do |attr|
        public_send(attr).blank?
      end

      return if missing_keys.empty?

      raise ConfigurationError,
            "CasinoClientSessionGuard configuration error: #{missing_keys.join(', ')} cannot be blank"
    end
  end
end