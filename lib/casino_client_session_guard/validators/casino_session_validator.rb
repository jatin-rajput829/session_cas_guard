# frozen_string_literal: true

require "httparty"

module CasinoClientSessionGuard
  module Validators
    # CasinoSessionValidator calls the CAS provider API to verify if a CAS ticket is still valid.
    # It handles network errors gracefully and logs failures for debugging.
    class CasinoSessionValidator
      include HTTParty

      # Structured results let callers distinguish between an invalid CAS ticket
      # and a temporary validation failure such as a timeout or connection error.
      VALID_RESULT = :valid
      INVALID_RESULT = :invalid
      ERROR_RESULT = :error

      # Parse responses as JSON by default
      format :json

      # Set short timeouts to fail fast if the CAS server is unresponsive.
      # This prevents the app from hanging when CAS is down.
      default_timeout 3
      open_timeout 2
      read_timeout 3

      def initialize(cas_service_url:, cas_ticket: nil)
        @base_url        = configuration.casino_base_url.to_s.chomp("/")
        @api_token       = configuration.casino_api_token.to_s
        @cas_ticket      = cas_ticket.to_s.strip
        @cas_service_url = cas_service_url.to_s.strip
        @casino_validation_api_endpoint = configuration.casino_validation_api_endpoint.to_s.sub(/^\//, "")
      end

      # Validates the CAS ticket by calling the CAS provider API and returns a structured result.
      # The heartbeat controller uses this extra detail to apply the configured fail-open/fail-closed policy.
      def validation_result
        # Ticket or service URL missing - cannot validate
        if @cas_service_url.blank? || @base_url.blank? || @api_token.blank?
          instrument_validator(false, reason: "missing_configuration", status: INVALID_RESULT)
          return invalid_result(reason: "missing_configuration")
        end

        # Make HTTP request to CAS provider API with authentication token
        response = self.class.get(
          "#{@base_url}/#{@casino_validation_api_endpoint}",
          headers: {
            'Authorization' => "Bearer #{@api_token}",
            'Accept'        => 'application/json'
          },
          query: {
            cas_service_url: @cas_service_url,
            cas_ticket: @cas_ticket
          }.compact_blank
        )

        # Check if request was successful and validation returned true
        unless response.success?
          instrument_validator(false, reason: "http_failure", http_success: false, status: ERROR_RESULT)
          return error_result(reason: "http_failure")
        end

        valid = response.parsed_response&.dig('valid') == true
        reason = valid ? "valid" : "invalid"
        status = valid ? VALID_RESULT : INVALID_RESULT

        instrument_validator(valid, reason: reason, http_success: true, status: status)
        result_payload(status: status, reason: reason)
      rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
        # Transport failures mean CAS never answered. The configured failure policy,
        # not the validator itself, decides whether that should end the local session.
        Rails.logger.warn(
          "[CasinoClientSessionGuard::Validators::CasinoSessionValidator] Network error: " \
          "#{e.class} - #{e.message}"
        )
        instrument_validator(false, reason: "network_error", error_class: e.class.name, status: ERROR_RESULT)
        error_result(reason: "network_error", error_class: e.class.name)
      rescue StandardError => e
        # Unexpected errors - log full details for investigation
        Rails.logger.error(
          "[CasinoClientSessionGuard::Validators::CasinoSessionValidator] Unexpected failure: " \
          "#{e.class} - #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
        )
        instrument_validator(false, reason: "unexpected_error", error_class: e.class.name, status: ERROR_RESULT)
        error_result(reason: "unexpected_error", error_class: e.class.name)
      end

      # Preserve the simple boolean API for callers that do not care about policy-aware outcomes.
      # Any non-valid result remains false here.
      def valid?
        validation_result[:status] == VALID_RESULT
      end

      private

      def configuration
        CasinoClientSessionGuard.configuration
      end

      def result_payload(status:, reason:, error_class: nil)
        {
          status: status,
          reason: reason,
          error_class: error_class
        }
      end

      def invalid_result(reason:)
        result_payload(status: INVALID_RESULT, reason: reason)
      end

      def error_result(reason:, error_class: nil)
        result_payload(status: ERROR_RESULT, reason: reason, error_class: error_class)
      end

      def instrument_validator(valid, reason:, status:, http_success: nil, error_class: nil)
        CasinoClientSessionGuard::Observability.instrument(
          "validator",
          valid: valid,
          status: status,
          reason: reason,
          http_success: http_success,
          error_class: error_class,
          ticket_present: @cas_ticket.present?,
          service_url_present: @cas_service_url.present?
        )
      end
    end
  end
end
