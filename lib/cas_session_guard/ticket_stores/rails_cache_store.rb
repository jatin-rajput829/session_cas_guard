module CasSessionGuard
  module TicketStores
    class RailsCacheStore
      def initialize(cache: Rails.cache, namespace: "cas_session_guard:slo")
        @cache = cache
        @namespace = namespace
      end

      def invalidate(ticket:, ttl:)
        cache.write(invalidated_key(ticket), true, expires_in: ttl)
      end

      def invalidated?(ticket:)
        cache.exist?(invalidated_key(ticket))
      end

      private

      attr_reader :cache, :namespace

      def invalidated_key(ticket)
        "#{namespace}:invalidated:#{ticket}"
      end
    end
  end
end
