# frozen_string_literal: true

### Sign-out detection
# The session manager checks whether the current CAS ticket has been marked as signed out:
# When the current ticket is marked as signed out:

# 1. The heartbeat or protected request treats the session as expired.
# 2. CasinoClientSessionGuard clears local CAS session values.
# 3. The browser receives an unauthorized response or CAS redirect.
# 4. The user must authenticate again.

module CasinoClientSessionGuard
  class SessionManager
    def initialize(session)
      @session = session
    end

    def expired?
      authenticated_at = parsed_authenticated_at
      return false if authenticated_at.nil?

      authenticated_at < session_validation.ago
    end

    def authenticated?
      session[user_key].present?
    end

    def mark_cas_session_validated!
      session[authenticated_at_key] = Time.current + validation_buffer
    end

    def initialize_authenticated_session!
      session[authenticated_at_key] ||= Time.current + validation_buffer
      session[token_key] ||= SecureRandom.hex(32)
    end

    def clear!
      session.delete(user_key)
      session.delete(authenticated_at_key)
      session.delete(ticket_key)
      session.delete(service_url_key)
      session.delete(token_key)
    end

    def heartbeat_token
      session[token_key]
    end

    def cas_ticket
      session[ticket_key]
    end

    def cas_service_url
      session[service_url_key]
    end

    private

    attr_reader :session

    def configuration
      CasinoClientSessionGuard.configuration
    end

    def user_key
      configuration.cas_user_key
    end

    def ticket_key
      configuration.cas_ticket_key
    end

    def service_url_key
      configuration.cas_service_url_key
    end

    def token_key
      configuration.keep_alive_token_key
    end

    def validation_buffer
      configuration.validation_buffer
    end

    def session_validation
      configuration.session_validation
    end

    def parsed_authenticated_at
      value = session[authenticated_at_key]
      return if value.blank?
      return value if value.respond_to?(:before?)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def authenticated_at_key
      :cas_authenticated_at
    end
  end
end
