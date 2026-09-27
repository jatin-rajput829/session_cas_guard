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
      unless valid_keep_alive_token?
        instrument_heartbeat("forbidden", reason: "invalid_keep_alive_token")
        return head :forbidden
      end

      # Second check: verify user is authenticated in local session
      unless session_manager.authenticated?
        instrument_heartbeat("unauthorized", reason: "not_authenticated")
        return render_unauthorized("not_authenticated")
      end

      if session_manager.ticket_invalidated?
        session_manager.clear!
        instrument_heartbeat("unauthorized", reason: "ticket_invalidated")
        return render_unauthorized("remote_session_invalid")
      end

      # Third check: verify the CAS ticket is still valid with CAS provider
      unless remote_session_valid?
        session_manager.clear!
        instrument_heartbeat("unauthorized", reason: "remote_session_invalid")
        return render_unauthorized("remote_session_invalid")
      end

      # All checks passed - update session timestamp to keep it alive
      session_manager.mark_cas_session_validated!
      instrument_heartbeat("ok", reason: "validated")

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
    # The validator can return either:
    # - `true` / `false` for the original boolean contract
    # - a structured hash like `{ status: :valid | :invalid | :error, reason: "..." }`
    # Only structured `:error` results participate in the configurable fail-open/fail-closed policy.
    def remote_session_valid?
      validator = CasinoClientSessionGuard.configuration.session_validator
      return false unless validator.respond_to?(:call)

      # Ask the validator to check the current ticket against CAS.
      # This can produce a boolean for legacy validators or a structured result for policy-aware validators.
      result = validator.call(
        cas_service_url: session_manager.cas_service_url,
        cas_ticket: session_manager.cas_ticket
      )

      normalize_remote_validation_result(result)
    rescue StandardError => error
      # If the validator itself crashes, apply the configured policy the same way we do
      # for transport failures returned by the structured validator path.
      Rails.logger.error(
        "[CasinoClientSessionGuard] remote CAS validation failed: " \
        "#{error.class}: #{error.message}"
      )

      instrument_heartbeat("validator_error", reason: error.class.name)
      remote_validation_failure_policy == :fail_open
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

    def instrument_heartbeat(outcome, reason:)
      CasinoClientSessionGuard::Observability.instrument(
        "heartbeat",
        outcome: outcome,
        reason: reason,
        authenticated: session_manager.authenticated?,
        ticket_present: session_manager.cas_ticket.present?
      )
    end

    # Convert validator output into a final allow/deny decision.
    # Legacy boolean validators stay strict to preserve backward compatibility.
    # Structured `:error` results are the only branch controlled by configuration.
    def normalize_remote_validation_result(result)
      return true if result == true
      return false if result == false
      return false unless result.is_a?(Hash)

      case result[:status]&.to_sym
      when :valid
        true
      when :invalid
        false
      when :error
        instrument_heartbeat("validator_error", reason: result[:reason].to_s)
        remote_validation_failure_policy == :fail_open
      else
        false
      end
    end

    def remote_validation_failure_policy
      CasinoClientSessionGuard.configuration.remote_validation_failure_policy
    end
  end
end
