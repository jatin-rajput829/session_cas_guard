# frozen_string_literal: true

require "httparty"

module CasinoClientSessionGuard
  module Validators
    # CasinoSessionValidator calls the CAS provider API to verify if a CAS ticket is still valid.
    # It handles network errors gracefully and logs failures for debugging.
    class CasinoSessionValidator
      include HTTParty

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

      # Validates the CAS ticket by calling the CAS provider API.
      # Returns true if the ticket is valid, false otherwise or if validation fails.
      def valid?
        # Ticket or service URL missing - cannot validate
        return false if @cas_service_url.blank? || @base_url.blank? || @api_token.blank?

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
        return false unless response.success?
      
        response.parsed_response&.dig('valid') == true
      rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
        # Network errors are recoverable - log as warning and fail open (session remains valid)
        # This prevents network issues from prematurely invalidating sessions
        Rails.logger.warn(
          "[CasinoClientSessionGuard::Validators::CasinoSessionValidator] Network error: " \
          "#{e.class} - #{e.message}"
        )
        false
      rescue StandardError => e
        # Unexpected errors - log full details for investigation
        Rails.logger.error(
          "[CasinoClientSessionGuard::Validators::CasinoSessionValidator] Unexpected failure: " \
          "#{e.class} - #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
        )
        false
      end

      private

      def configuration
        CasinoClientSessionGuard.configuration
      end
    end
  end
end
