# frozen_string_literal: true

require "httparty"

module CasinoClientSessionGuard
  module Validators
    class CasinoSessionValidator
      include HTTParty

      # Explicit timeouts: fail fast if the CAS server hangs
      default_timeout 3
      open_timeout 2
      read_timeout 3

      def initialize(cas_service_url:, cas_ticket: nil)
        @base_url        = configuration.casino_base_url.to_s.chomp("/")
        @api_token       = configuration.casino_api_token.to_s
        @cas_ticket      = cas_ticket.to_s.strip
        @cas_service_url = cas_service_url.to_s.strip
        @casino_validation_api_endpoint = configuration.casino_validation_api_endpoint
      end

      def valid?
        return false if @cas_service_url.blank? || @base_url.blank? || @api_token.blank?

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

        return false unless response.success?
      
        response.parsed_response&.dig('valid') == true
      rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
        Rails.logger.warn("[CasinoClientSessionGuard::Validators::CasinoSessionValidator] Network error: #{error.class} - #{error.message}")
        false
      rescue StandardError => e
        Rails.logger.error(
          "[CasinoClientSessionGuard::Validators::CasinoSessionValidator] Unexpected failure: #{error.class} - #{error.message}\n" \
          "#{error.backtrace&.first(3)&.join("\n")}"
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
