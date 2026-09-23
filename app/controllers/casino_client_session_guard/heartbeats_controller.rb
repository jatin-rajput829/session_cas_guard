# frozen_string_literal: true

# Heartbeat Controller
# The heartbeat is the browser-side enforcement mechanism for session validation.
# How it works:
#   1. Browser sends heartbeat request every N seconds with authentication token
#   2. Server validates the CAS ticket with the CAS provider
#   3. CAS server responds if ticket is still valid (not signed out)
#   4. If ticket is invalid, server clears local session
#   5. Browser receives unauthorized response and shows redirect modal

module CasinoClientSessionGuard
  class HeartbeatsController < ActionController::Base

    # Heartbeat endpoint - checks if the user's CAS session is still valid.
    # Returns 200 if session is valid, 401 with redirect URL if session is expired.
    def show
      # First check: verify the browser sent a valid keep-alive token
      # This token is stored in an HTML meta tag on the client side
      return head :forbidden unless valid_keep_alive_token?

      # Second check: verify user is authenticated in local session
      return render_unauthorized("not_authenticated") unless session_manager.authenticated?

      # Third check: verify the CAS ticket is still valid with CAS provider
      unless remote_session_valid?
        session_manager.clear!
        return render_unauthorized("remote_session_invalid")
      end

      # All checks passed - update session timestamp to keep it alive
      session_manager.mark_cas_session_validated!

      render json: { ok: true }, status: :ok
    end

    private

    # Creates a session manager for the current request
    def session_manager
      @session_manager ||= SessionManager.new(session)
    end

    # Validates the keep-alive token sent by the browser.
    # Uses secure comparison to prevent timing attacks.
    # The token is hashed before comparison for extra security.
    def valid_keep_alive_token?
      supplied = request.headers["X-Keep-Alive-Token"].to_s
      expected = session_manager.heartbeat_token.to_s

      # Both token and session must have a token
      return false if supplied.blank? || expected.blank?

      # Compare tokens securely (constant-time comparison)
      # Both are hashed to prevent information leakage
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.digest(supplied),
        Digest::SHA256.digest(expected)
      )
    end

    # Validates the user's CAS ticket with the CAS provider.
    # Calls the configured validator (typically the CasinoSessionValidator).
    # Returns false if validation fails or an error occurs.
    def remote_session_valid?
      validator = CasinoClientSessionGuard.configuration.session_validator
      return false unless validator.respond_to?(:call)

      # Call the validator with the CAS ticket and service URL
      validator.call(
        cas_service_url: session_manager.cas_service_url,
        cas_ticket: session_manager.cas_ticket
      ) == true
    rescue StandardError => error
      # Log validation errors for debugging but fail safely
      Rails.logger.error(
        "[CasinoClientSessionGuard] remote CAS validation failed: " \
        "#{error.class}: #{error.message}"
      )

      false
    end

    # Returns a JSON error response with the CAS login URL.
    # The client receives this and shows a modal with a redirect button.
    def render_unauthorized(reason)
      render json: {
        ok: false,
        reason: reason,
        redirect_url: reauthentication_url
      }, status: :unauthorized
    end

    # Determines the URL to send the user to for re-authentication.
    # Can be customized via configuration (e.g., to send to a login page).
    def reauthentication_url
      callback = CasinoClientSessionGuard.configuration.reauthentication_url

      return callback.call(self) if callback.respond_to?(:call)

      raise ConfigurationError,
            "CasinoClientSessionGuard.configuration.reauthentication_url must be configured"
    end
  end
end
