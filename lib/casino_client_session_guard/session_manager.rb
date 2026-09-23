# frozen_string_literal: true

# SessionManager handles CAS session lifecycle management.
# It stores and retrieves session data like user info, tickets, and validation timestamps.
# 
# Sign-out detection flow:
# 1. CAS server marks the ticket as signed out
# 2. SessionManager detects this during validation
# 3. Session is cleared and user sees unauthorized response
# 4. User is redirected to CAS login page

module CasinoClientSessionGuard
  class SessionManager
    def initialize(session)
      @session = session
    end

    # Checks if the current session has expired based on the last validation time.
    # Returns true if the time since last authentication exceeds the allowed validation period.
    def expired?
      authenticated_at = parsed_authenticated_at
      return false if authenticated_at.nil?

      authenticated_at < session_validation.ago
    end

    # Checks if there is a valid user in the current session.
    # Returns true if a user is logged in, false otherwise.
    def authenticated?
      session[user_key].present?
    end

    # Updates the session validation timestamp to the current time plus a buffer.
    # This keeps the session alive and prevents it from expiring immediately.
    def mark_cas_session_validated!
      session[authenticated_at_key] = Time.current + validation_buffer
    end

    # Sets up a new authenticated session with initial timestamp and heartbeat token.
    # The token is used by the browser to prove the request is coming from an authenticated session.
    def initialize_authenticated_session!
      session[authenticated_at_key] ||= Time.current + validation_buffer
      session[token_key] ||= SecureRandom.hex(32)
    end

    # Removes all CAS-related session data.
    # Called when user logs out or session is terminated.
    def clear!
      session.delete(user_key)
      session.delete(authenticated_at_key)
      session.delete(ticket_key)
      session.delete(service_url_key)
      session.delete(token_key)
    end

    # Returns the heartbeat token used to verify browser requests.
    def heartbeat_token
      session[token_key]
    end

    # Returns the CAS ticket for the current session.
    def cas_ticket
      session[ticket_key]
    end

    # Returns the service URL that CAS uses to validate the ticket.
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

    # Safely parses the authentication timestamp from session storage.
    # Handles both Time objects and strings, returning nil if parsing fails.
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
