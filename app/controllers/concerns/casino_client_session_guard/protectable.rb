# frozen_string_literal: true

module CasinoClientSessionGuard
  module Protectable
    extend ActiveSupport::Concern

    included do
      before_action :enforce_cas_session
    end

    private

    def enforce_cas_session
      manager = session_manager

      if manager.authenticated? && manager.expired?
        manager.clear!
      end

      if manager.authenticated?
        manager.initialize_authenticated_session!
        return
      end

      if turbo_or_xhr_request?
        handle_missing_cas_session
        return
      end

      # Let CASClient validate the ticket param and populate the session first.
      filter_passed = CASClient::Frameworks::Rails::Filter.filter(self, )
      return unless filter_passed

      if session[manager_user_key].present?
        manager.initialize_authenticated_session!
      else
        handle_missing_cas_session
      end
    end

    def perform_cas_logout(redirect_url: nil)
      manager = session_manager
      ticket = manager.cas_ticket

      manager.clear!

      if ticket.present?
        CasinoClientSessionGuard.configuration.sign_out_store.invalidate(
          ticket: ticket,
          ttl: CasinoClientSessionGuard.configuration.sign_out_ttl
        )
      end

      CASClient::Frameworks::Rails::Filter.logout(
        self,
        redirect_url || configured_fallback_url
      )
    end

    def handle_missing_cas_session
      target_url = safe_cas_redirect_target
      session[CasinoClientSessionGuard.configuration.cas_service_url_key] = target_url

      login_url = cas_login_url(target_url)

      if turbo_or_xhr_request?
        response.set_header("Turbo-Visit-Location", login_url)
        response.set_header("X-Session-Expired", "true")
        head :unauthorized
        return
      end
    end

    def cas_login_url(service_url)
      client = CASClient::Frameworks::Rails::Filter.client
      client.add_service_to_login_url(service_url)
    end

    def session_manager
      @session_manager ||= CasinoClientSessionGuard::SessionManager.new(session)
    end

    def turbo_or_xhr_request?
      request.headers["Turbo-Frame"].present? ||
        request.xhr? ||
        request.headers["X-Requested-With"] == "XMLHttpRequest"
    end

    def safe_cas_redirect_target
      candidate = same_origin_referer || request.original_url

      strip_cas_ticket(candidate)
    rescue URI::InvalidURIError, ArgumentError
      configured_fallback_url
    end

    def same_origin_referer
      return if request.referer.blank?

      referer_uri = URI.parse(request.referer)

      return unless referer_uri.is_a?(URI::HTTP)
      return unless referer_uri.scheme == request.scheme
      return unless referer_uri.host&.casecmp?(request.host)
      return unless referer_uri.port == request.port

      request.referer
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def strip_cas_ticket(url)
      uri = URI.parse(url)
      query = Rack::Utils.parse_nested_query(uri.query)
      query.delete("ticket")

      uri.query = query.empty? ? nil : Rack::Utils.build_query(query)
      uri.to_s
    end

    def configured_fallback_url
      callback = CasinoClientSessionGuard.configuration.service_url

      return callback.call(self) if callback.respond_to?(:call)

      request.base_url
    end

    def manager_user_key
      CasinoClientSessionGuard.configuration.cas_user_key
    end
  end
end
