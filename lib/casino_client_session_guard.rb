# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/object/blank"
require "active_support/security_utils"
require "digest"
require "securerandom"

require_relative "casino_client_session_guard/version"
require_relative "casino_client_session_guard/configuration"
require_relative "casino_client_session_guard/session_manager"
require_relative "casino_client_session_guard/validators/casino_session_validator"
require_relative "casino_client_session_guard/configuration_error"
require_relative "casino_client_session_guard/ticket_stores/rails_cache_store"
require_relative "../app/helpers/casino_client_session_guard/application_helper"

# CasinoClientSessionGuard is a Rails gem that manages CAS (Central Authentication Service) sessions.
# It monitors user sessions through heartbeats and keeps them in sync with CAS server.
# When a user logs out from CAS, this gem detects it and clears the local session.
module CasinoClientSessionGuard
  class << self
    # Returns the global configuration object. Creates a new one on first access.
    def configuration
      @configuration ||= Configuration.new
    end

    # Allows setting up the gem by passing a block with configuration options.
    # Example: CasinoClientSessionGuard.configure { |config| config.heartbeat_path = "/heartbeat" }
    def configure
      yield(configuration)
      configuration.validate!
    end

    # Resets the configuration back to defaults. Mainly used in testing.
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require_relative "casino_client_session_guard/engine" if defined?(Rails::Engine)
