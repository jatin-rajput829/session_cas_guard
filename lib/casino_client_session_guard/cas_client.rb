# frozen_string_literal: true

module CasinoClientSessionGuard
  module CasClient
    module FilterRedirectPatch
      def redirect_to_cas_for_authentication(controller)
        super
      rescue StandardError
        controller.send(:redirect_to, login_url(controller), allow_other_host: true)
      end

      def logout(controller, service = nil)
        super
      rescue StandardError
        referer = service || controller.request.referer
        controller.send(:redirect_to, client.logout_url(referer), allow_other_host: true)
      end
    end

    class << self
      def configure!
        return false unless configured?

        configure_filter
        patch_redirects if configuration.allow_other_host_redirects
        true
      end

      def filter(controller)
        ensure_configured!
        configure!
        filter_class.filter(controller)
      rescue StandardError
        raise unless configuration.allow_other_host_redirects

        controller.send(:redirect_to, filter_class.login_url(controller), allow_other_host: true)
        false
      end

      def logout(controller, service = nil)
        ensure_configured!
        configure!
        filter_class.logout(controller, service)
      rescue StandardError
        raise unless configuration.allow_other_host_redirects

        referer = service || controller.request.referer
        controller.send(:redirect_to, filter_class.client.logout_url(referer), allow_other_host: true)
      end

      def login_url_for(service_url)
        ensure_configured!
        configure!
        filter_class.client.add_service_to_login_url(service_url)
      end

      private

      def configuration
        CasinoClientSessionGuard.configuration
      end

      def configure_filter
        filter_class.configure(
          cas_base_url: resolved_cas_base_url,
          login_url: resolved_login_url,
          logger: resolved_logger,
          encode_extra_attributes_as: configuration.encode_extra_attributes_as
        )
      end

      def configured?
        resolved_cas_base_url.present? || resolved_login_url.present?
      end

      def ensure_configured!
        return if configured?

        raise ConfigurationError,
              "CasinoClientSessionGuard configuration error: cas_base_url or cas_login_url cannot be blank"
      end

      def resolved_cas_base_url
        configuration.cas_base_url.presence || configuration.casino_base_url
      end

      def resolved_login_url
        return configuration.cas_login_url if configuration.cas_login_url.present?
        return if resolved_cas_base_url.blank?

        [resolved_cas_base_url.sub(%r{/$}, ""), "login"].join("/")
      end

      def resolved_logger
        configuration.cas_logger || (defined?(Rails) ? Rails.logger : nil)
      end

      def patch_redirects
        singleton = filter_class.singleton_class
        return if singleton < FilterRedirectPatch

        singleton.prepend(FilterRedirectPatch)
      end

      def filter_class
        CASClient::Frameworks::Rails::Filter
      end
    end
  end
end