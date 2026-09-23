module CasinoClientSessionGuard
  module TicketStores
    # RailsCacheStore tracks CAS tickets that have been signed out using Rails.cache.
    # This prevents users from using old tickets even if they log out from CAS.
    class RailsCacheStore
      def initialize(cache: Rails.cache, namespace: "cas_session_guard:slo")
        @cache = cache
        @namespace = namespace
      end

      # Marks a CAS ticket as invalidated.
      # The ticket will be stored in cache until TTL (time to live) expires.
      # After TTL, the cache entry is automatically cleaned up by Rails cache.
      def invalidate(ticket:, ttl:)
        cache.write(invalidated_key(ticket), true, expires_in: ttl)
      end

      # Checks if a CAS ticket has been marked as invalidated (logged out).
      # Returns true if ticket is in the invalidated cache, false otherwise.
      def invalidated?(ticket:)
        cache.exist?(invalidated_key(ticket))
      end

      private

      attr_reader :cache, :namespace

      # Creates a unique cache key for the ticket using the namespace.
      # Example: "cas_session_guard:slo:invalidated:TGT-abc123"
      def invalidated_key(ticket)
        "#{namespace}:invalidated:#{ticket}"
      end
    end
  end
end
