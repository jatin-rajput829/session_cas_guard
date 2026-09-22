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

module CasinoClientSessionGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.validate!
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require_relative "casino_client_session_guard/engine" if defined?(Rails::Engine)
