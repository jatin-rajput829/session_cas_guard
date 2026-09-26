# frozen_string_literal: true

module CasinoClientSessionGuard
  class SingleLogoutMiddleware
    OK_RESPONSE = [200, { "Content-Type" => "text/plain", "Content-Length" => "0" }, []].freeze
    BAD_REQUEST_RESPONSE = [400, { "Content-Type" => "text/plain", "Content-Length" => "0" }, []].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      return app.call(env) unless single_logout_request?(request)

      logout_request = build_logout_request(request)
      return app.call(env) if logout_request.tickets.empty?

      logout_request.invalidate!
      OK_RESPONSE
    rescue REXML::ParseException => error
      Rails.logger.warn(
        "[CasinoClientSessionGuard] single logout payload parse failed: " \
        "#{error.class}: #{error.message}"
      )
      BAD_REQUEST_RESPONSE
    end

    private

    attr_reader :app

    def single_logout_request?(request)
      configuration.single_logout_enabled && request.post? && build_logout_request(request).tickets.any?
    end

    def configuration
      CasinoClientSessionGuard.configuration
    end

    def build_logout_request(request)
      post_params = request.POST
      raw_payload = request.body.read
      request.body.rewind if request.body.respond_to?(:rewind)

      CasinoClientSessionGuard::SingleLogoutRequest.new(
        ticket_param: post_params["ticket"] || request.GET["ticket"],
        logout_request_param: post_params["logoutRequest"] || request.GET["logoutRequest"],
        raw_payload: raw_payload,
        media_type: request.media_type
      )
    end
  end
end