# frozen_string_literal: true

# Stub CASClient for testing when the gem is not installed
unless defined?(CASClient)
  module CASClient
    module Frameworks
      module Rails
        class Filter
          class << self
            attr_reader :configuration
          end

          def self.filter(controller, options = {})
            true
          end

          def self.configure(options = {})
            @configuration = options
          end

          def self.login_url(controller)
            configuration && configuration[:login_url]
          end

          def self.client
            Client.new
          end

          def self.logout(controller, redirect_url = nil)
            controller.redirect_to(redirect_url || "/")
          end
        end

        class Client
          def add_service_to_login_url(service_url)
            "https://cas.example.com/login?service=#{CGI.escape(service_url)}"
          end

          def logout_url(service_url = nil)
            return "https://cas.example.com/logout" if service_url.nil?

            "https://cas.example.com/logout?service=#{CGI.escape(service_url)}"
          end
        end
      end
    end
  end
end
