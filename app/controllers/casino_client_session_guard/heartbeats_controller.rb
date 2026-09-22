# frozen_string_literal: true

### Heartbeat behavior
# The heartbeat remains the browser-side enforcement mechanism.
# CAS sign-out notification received
#   ↓
# Ticket marked as signed out immediately
#   ↓
# Next heartbeat detects the ticket
#   ↓
# Local Rails session is cleared
#   ↓
# Browser redirects to CAS login

module CasinoClientSessionGuard
  class HeartbeatsController < ActionController::Base

    def show
      return head :forbidden unless valid_keep_alive_token?
      return render_unauthorized("not_authenticated") unless session_manager.authenticated?

      unless remote_session_valid?
        session_manager.clear!
        return render_unauthorized("remote_session_invalid")
      end

      session_manager.mark_cas_session_validated!

      render json: { ok: true }, status: :ok
    end

    private

    def session_manager
      @session_manager ||= SessionManager.new(session)
    end

    def valid_keep_alive_token?
      supplied = request.headers["X-Keep-Alive-Token"].to_s
      expected = session_manager.heartbeat_token.to_s

      return false if supplied.blank? || expected.blank?

      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.digest(supplied),
        Digest::SHA256.digest(expected)
      )
    end

    def remote_session_valid?
      validator = CasinoClientSessionGuard.configuration.session_validator
      return false unless validator.respond_to?(:call)

      validator.call(
        cas_service_url: session_manager.cas_service_url,
        cas_ticket: session_manager.cas_ticket
      ) == true
    rescue StandardError => error
      Rails.logger.error(
        "[CasinoClientSessionGuard] remote CAS validation failed: " \
        "#{error.class}: #{error.message}"
      )

      false
    end

    def render_unauthorized(reason)
      render json: {
        ok: false,
        reason: reason,
        redirect_url: reauthentication_url
      }, status: :unauthorized
    end

    def reauthentication_url
      callback = CasinoClientSessionGuard.configuration.reauthentication_url

      return callback.call(self) if callback.respond_to?(:call)

      raise ConfigurationError,
            "CasinoClientSessionGuard.configuration.reauthentication_url must be configured"
    end
  end
end
