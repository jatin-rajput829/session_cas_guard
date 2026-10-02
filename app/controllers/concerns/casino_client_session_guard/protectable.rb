# frozen_string_literal: true

module CasinoClientSessionGuard
  # Protectable is a concern that enforces CAS session validation on controller actions.
  # Include this in your controller to require active CAS authentication.
  #
  # Usage:
  #   class MyController < ApplicationController
  #     include CasinoClientSessionGuard::Protectable
  #   end
  module Protectable
    extend ActiveSupport::Concern

    included do
      # Run CAS session enforcement before each action
      before_action :enforce_cas_session
    end

    private

    # Main enforcement logic - validates CAS session before allowing access to an action.
    # 1. Clears expired sessions
    # 2. Allows authenticated users to continue
    # 3. Validates ticket with CAS server using CASClient filter
    # 4. Handles AJAX/Turbo requests differently (returns headers instead of redirect)
    def enforce_cas_session
      manager = session_manager

      # Clear session if it has expired but user is still marked as authenticated
      session_expired = manager.authenticated? && manager.expired?
      ticket_invalidated = manager.authenticated? && manager.ticket_invalidated?

      if session_expired || ticket_invalidated
        manager.clear!
      end

      # User is still authenticated and not expired - proceed with request
      if manager.authenticated?
        manager.initialize_authenticated_session!
        instrument_protectable("allowed", reason: "authenticated")
        return
      end

      if session_expired
        instrument_protectable("cleared", reason: "session_expired")
      elsif ticket_invalidated
        instrument_protectable("cleared", reason: "ticket_invalidated")
      end

      # AJAX/Turbo requests - return special headers instead of redirecting
      if turbo_or_xhr_request?
        handle_missing_cas_session
        return
      end

      # Regular page request - use CASClient gem to validate the ticket parameter
      # This connects to CAS server and populates session with user info
      filter_passed = CasinoClientSessionGuard::CasClient.filter(self)
      instrument_protectable("cas_filter", reason: filter_passed ? "passed" : "halted")
      return unless filter_passed

      # After CASClient validates the ticket, check if user is now in session
      if session[manager_user_key].present?
        manager.initialize_authenticated_session!
        instrument_protectable("allowed", reason: "authenticated_via_cas")
      else
        handle_missing_cas_session
      end
    end

    # Performs a complete logout from CAS.
    # Clears local session, invalidates the CAS ticket, and redirects to CAS logout.
    def perform_cas_logout(redirect_url: nil)
      manager = session_manager
      ticket = manager.cas_ticket

      # Clear local session immediately
      manager.clear!

      # Mark the CAS ticket as invalidated to prevent reuse
      if ticket.present?
        CasinoClientSessionGuard.configuration.sign_out_store.invalidate(
          ticket: ticket,
          ttl: CasinoClientSessionGuard.configuration.sign_out_ttl
        )
      end

      CasinoClientSessionGuard::Observability.instrument(
        "logout",
        outcome: "performed",
        ticket_present: ticket.present?
      )

      # Redirect to CAS logout with optional redirect URL
      CasinoClientSessionGuard::CasClient.logout(
        self,
        redirect_url || configured_fallback_url
      )
    end

    # Handles cases where CAS session is missing or invalid.
    # For AJAX/Turbo requests: sets headers to trigger frontend redirect
    # For regular requests: redirects to CAS login page
    def handle_missing_cas_session
      target_url = safe_cas_redirect_target
      session[CasinoClientSessionGuard.configuration.cas_service_url_key] = target_url

      login_url = cas_login_url(target_url)

      if turbo_or_xhr_request?
        instrument_protectable("rejected", reason: "missing_session", transport: "xhr")
        # Tell Turbo/AJAX client where to redirect the user
        response.set_header("Turbo-Visit-Location", login_url)
        response.set_header("X-Session-Expired", "true")
        head :unauthorized
        return
      end

      instrument_protectable("rejected", reason: "missing_session", transport: "html")
      # Regular redirect to CAS login
      redirect_to login_url
    end

    # Builds the CAS login URL with the current page as the service (redirect target).
    def cas_login_url(service_url)
      CasinoClientSessionGuard::CasClient.login_url_for(service_url)
    end

    # Returns a session manager instance for the current request.
    # Cached to avoid creating multiple instances per request.
    def session_manager
      @session_manager ||= CasinoClientSessionGuard::SessionManager.new(session)
    end

    # Checks if this is an AJAX request or Turbo request.
    # These requests need special handling (headers) instead of HTML redirects.
    def turbo_or_xhr_request?
      request.format.turbo_stream? ||
        request.headers["Turbo-Frame"].present? ||
        request.xhr? ||
        request.headers["X-Requested-With"] == "XMLHttpRequest"
    end

    # Determines the safe redirect target after CAS login.
    # Uses the referer if it's same-origin, otherwise uses the current URL.
    # Removes the CAS ticket parameter to avoid re-validation issues.
    def safe_cas_redirect_target
      candidate = same_origin_referer || request.original_url

      strip_cas_ticket(candidate)
    rescue URI::InvalidURIError, ArgumentError
      # If URL parsing fails, fall back to the configured default
      configured_fallback_url
    end

    # Validates that the referer is from the same origin (scheme, host, port).
    # Returns the referer if valid, nil otherwise.
    # This prevents open redirect vulnerabilities.
    def same_origin_referer
      return if request.referer.blank?

      referer_uri = URI.parse(request.referer)

      # Ensure it's an HTTP(S) URL
      return unless referer_uri.is_a?(URI::HTTP)
      # Ensure same scheme (http vs https)
      return unless referer_uri.scheme == request.scheme
      # Ensure same host (case-insensitive comparison)
      return unless referer_uri.host&.casecmp?(request.host)
      # Ensure same port
      return unless referer_uri.port == request.port

      request.referer
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    # Removes the CAS ticket parameter from a URL.
    # The ticket is single-use and should not be included in redirect URLs.
    def strip_cas_ticket(url)
      uri = URI.parse(url)
      query = Rack::Utils.parse_nested_query(uri.query)
      query.delete("ticket")

      uri.query = query.empty? ? nil : Rack::Utils.build_query(query)
      uri.to_s
    end

    # Returns the fallback URL to redirect to after logout or if no referer is available.
    # Uses a configured callable if available, otherwise returns the site root.
    def configured_fallback_url
      callback = CasinoClientSessionGuard.configuration.service_url

      return callback.call(self) if callback.respond_to?(:call)

      request.base_url
    end

    # Returns the session key name for the CAS user.
    def manager_user_key
      CasinoClientSessionGuard.configuration.cas_user_key
    end

    def instrument_protectable(outcome, reason:, transport: nil)
      CasinoClientSessionGuard::Observability.instrument(
        "protectable",
        outcome: outcome,
        reason: reason,
        transport: transport,
        authenticated: session_manager.authenticated?
      )
    end
  end
end
