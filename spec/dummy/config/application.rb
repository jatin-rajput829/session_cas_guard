# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require "action_view/railtie"

require_relative "../../../lib/casino_client_session_guard"

module Dummy
  class Application < Rails::Application
    config.load_defaults 6.1
    config.eager_load = false
    config.secret_key_base = "test_secret_key_base"
    config.session_store :cookie_store, key: "_dummy_session"
  end
end

Dummy::Application.initialize!
