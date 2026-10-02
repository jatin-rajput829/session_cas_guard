# frozen_string_literal: true

require "cgi"
require "json"
require "rexml/document"
require "rexml/xpath"
require "uri"

require "httparty"

module CasinoClientSessionGuard
  module CasClient
    class TicketValidator
      include HTTParty

      NS = { "cas" => "http://www.yale.edu/tp/cas" }.freeze

      default_timeout 5
      open_timeout 2
      read_timeout 3

      def initialize(service_url:, ticket:, validate_url:, logger: nil)
        @service_url = service_url.to_s
        @ticket = ticket.to_s
        @validate_url = validate_url.to_s
        @logger = logger
      end

      def call
        response = self.class.get(
          @validate_url,
          headers: { "Accept" => "application/xml" },
          query: {
            service: @service_url,
            ticket: @ticket
          }
        )

        return failure_result("http_failure") unless response.success?

        parse_response(response.body.to_s)
      rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
        log(:warn, "CAS ticket validation failed: #{e.class} - #{e.message}")
        failure_result("network_error")
      rescue REXML::ParseException => e
        log(:warn, "CAS ticket validation returned invalid XML: #{e.message}")
        failure_result("invalid_xml")
      end

      private

      def parse_response(body)
        document = REXML::Document.new(body)
        user_node = first_node(document, "//cas:authenticationSuccess/cas:user", "//authenticationSuccess/user")
        return failure_result(authentication_failure_code(document) || "invalid_ticket") if user_node.nil?

        {
          success: true,
          username: user_node.text.to_s,
          extra_attributes: extract_attributes(document)
        }
      end

      def extract_attributes(document)
        attributes_node = first_node(
          document,
          "//cas:authenticationSuccess/cas:attributes",
          "//authenticationSuccess/attributes"
        )
        return {} unless attributes_node

        attributes = {}
        attributes_node.elements.each do |element|
          key = element.name.to_s.sub(/^.*:/, "")
          value = cast_attribute_value(element.text)

          if attributes.key?(key)
            attributes[key] = Array(attributes[key]) << value
          else
            attributes[key] = value
          end
        end

        attributes
      end

      def authentication_failure_code(document)
        failure = first_node(document, "//cas:authenticationFailure", "//authenticationFailure")
        return unless failure

        failure.attributes["code"].presence || "authentication_failure"
      end

      def first_node(document, *paths)
        paths.lazy.map { |path| REXML::XPath.first(document, path, NS) }.find(&:present?)
      end

      def cast_attribute_value(value)
        string = value.to_s.strip
        return true if string.casecmp?("true")
        return false if string.casecmp?("false")

        string
      end

      def failure_result(reason)
        { success: false, reason: reason }
      end

      def log(level, message)
        @logger&.public_send(level, "[CasinoClientSessionGuard::CasClient] #{message}")
      end
    end

    class << self
      def configure!
        true
      end

      def filter(controller)
        ensure_configured!
        ticket = controller.params[:ticket].presence
        service_url = service_url_for(controller)

        return redirect_to_login(controller, service_url) if ticket.blank?

        result = TicketValidator.new(
          service_url: service_url,
          ticket: ticket,
          validate_url: resolved_validate_url,
          logger: resolved_logger
        ).call

        return redirect_to_login(controller, service_url) unless result[:success]

        store_session(controller.session, result: result, ticket: ticket, service_url: service_url)
        true
      rescue StandardError
        raise unless configuration.allow_other_host_redirects

        controller.send(:redirect_to, login_url_for(service_url), allow_other_host: true)
        false
      end

      def logout(controller, service = nil)
        ensure_configured!
        redirect_to_url(controller, logout_url_for(service || controller.request.referer))
      rescue StandardError
        raise unless configuration.allow_other_host_redirects

        referer = service || controller.request.referer
        controller.send(:redirect_to, logout_url_for(referer), allow_other_host: true)
      end

      def login_url_for(service_url)
        ensure_configured!
        uri = parsed_uri(resolved_login_url)
        query = Rack::Utils.parse_nested_query(uri.query)
        query["service"] = service_url
        uri.query = Rack::Utils.build_query(query)
        uri.to_s
      end

      def logout_url_for(service_url = nil)
        ensure_configured!
        uri = parsed_uri(resolved_logout_url)
        return uri.to_s if service_url.blank?

        query = Rack::Utils.parse_nested_query(uri.query)
        query["destination"] = service_url
        query["gateway"] = true
        uri.query = Rack::Utils.build_query(query)
        uri.to_s
      end

      private

      def configuration
        CasinoClientSessionGuard.configuration
      end

      def configured?
        resolved_cas_base_url.present? || resolved_login_url.present? || resolved_validate_url.present?
      end

      def ensure_configured!
        return if configured?

        raise ConfigurationError,
              "CasinoClientSessionGuard configuration error: cas_base_url or cas_login_url cannot be blank"
      end

      def resolved_cas_base_url
        configuration.cas_base_url.presence || configuration.casino_base_url
      end

      def resolved_login_url
        return configuration.cas_login_url if configuration.cas_login_url.present?
        return if resolved_cas_base_url.blank?

        [resolved_cas_base_url.sub(%r{/$}, ""), "login"].join("/")
      end

      def resolved_logout_url
        return configuration.cas_logout_url if configuration.cas_logout_url.present?
        return if resolved_cas_base_url.blank?

        [resolved_cas_base_url.sub(%r{/$}, ""), "logout"].join("/")
      end

      def resolved_validate_url
        return configuration.cas_validate_url if configuration.cas_validate_url.present?
        return if resolved_cas_base_url.blank?

        [resolved_cas_base_url.sub(%r{/$}, ""), "proxyValidate"].join("/")
      end

      def resolved_logger
        configuration.cas_logger || (defined?(Rails) ? Rails.logger : nil)
      end

      def parsed_uri(url)
        URI.parse(url.to_s)
      end

      def redirect_to_login(controller, service_url)
        redirect_to_url(controller, login_url_for(service_url))
        false
      end

      def redirect_to_url(controller, url)
        options = configuration.allow_other_host_redirects ? { allow_other_host: true } : {}
        controller.redirect_to(url, **options)
      rescue StandardError
        raise unless configuration.allow_other_host_redirects

        controller.redirect_to(url, allow_other_host: true)
      end

      def service_url_for(controller)
        strip_ticket(controller.request.original_url)
      end

      def strip_ticket(url)
        uri = URI.parse(url)
        query = Rack::Utils.parse_nested_query(uri.query)
        query.delete("ticket")
        uri.query = query.empty? ? nil : Rack::Utils.build_query(query)
        uri.to_s
      end

      def store_session(session, result:, ticket:, service_url:)
        session[configuration.cas_user_key] = result[:username]
        session[configuration.cas_ticket_key] = ticket
        session[configuration.cas_service_url_key] = service_url

        extra_attributes = result[:extra_attributes]
        return if configuration.cas_extra_attributes_key.blank? || extra_attributes.blank?

        session[configuration.cas_extra_attributes_key] = encoded_attributes(extra_attributes)
      end

      def encoded_attributes(extra_attributes)
        return extra_attributes.to_json if configuration.encode_extra_attributes_as == :json

        extra_attributes
      end
    end
  end
end