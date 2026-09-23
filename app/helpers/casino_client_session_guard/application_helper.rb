# frozen_string_literal: true

module CasinoClientSessionGuard
  module ApplicationHelper
    # Renders the session expiration warning modal partial.
    # This shows the user that their session is about to expire with a countdown timer.
    def render_cas_session_redirect_modal
      render "casino_client_session_guard/session_redirect_modal"
    end

    # Returns the icon to display in the session expiration modal.
    # Uses a custom icon if configured, falls back to tabler_icon or a warning symbol.
    def cas_session_redirect_icon
      icon = CasinoClientSessionGuard.configuration.modal_icon

      # If a callable (lambda/proc) is configured, call it with the view context
      return icon.call(self) if icon.respond_to?(:call)

      # If a string or HTML is configured, return it as safe HTML
      return icon.html_safe if icon.present?

      # Use tabler_icon gem if available, otherwise use a basic warning symbol
      if respond_to?(:tabler_icon)
        tabler_icon(
          "alert-triangle",
          class: "icon icon-lg text-warning mb-2",
          aria: { hidden: true }
        )
      else
        content_tag(
          :span,
          "⚠",
          class: "cas-session-redirect-modal__icon text-warning mb-2",
          aria: { hidden: true }
        )
      end
    end

    # Generates HTML meta tags needed by the browser-side session guard script.
    # These meta tags contain the heartbeat token, URL, and interval for session monitoring.
    def cas_session_guard_meta_tags
      safe_join(
        [
          # Token used to authenticate heartbeat requests from the browser
          tag.meta(
            name: "cas-session-guard-token",
            content: session[CasinoClientSessionGuard.configuration.keep_alive_token_key].to_s
          ),
          # URL where the browser should send heartbeat requests
          tag.meta(
            name: "cas-session-guard-heartbeat-url",
            content: CasinoClientSessionGuard.configuration.heartbeat_path
          ),
          # How often (in milliseconds) the browser should send heartbeat requests
          tag.meta(
            name: "cas-session-guard-heartbeat-interval",
            content: (
              CasinoClientSessionGuard.configuration.heartbeat_interval.to_f * 1000
            ).to_i
          )
        ],
        "\n"
      )
    end

    # Returns the title text for the session expiration modal.
    def cas_session_modal_title
      CasinoClientSessionGuard.configuration.modal_title
    end

    # Returns the main message text shown in the session expiration modal.
    def cas_session_modal_message
      CasinoClientSessionGuard.configuration.modal_message
    end

    # Returns the detail/description text shown below the main message.
    def cas_session_modal_detail
      CasinoClientSessionGuard.configuration.modal_detail
    end

    # Returns the countdown duration (in seconds) before automatic redirect.
    def cas_session_modal_countdown_seconds
      CasinoClientSessionGuard.configuration.modal_countdown_seconds
    end

    # Returns the text shown while the modal is redirecting the browser.
    def cas_session_modal_redirecting_text
      CasinoClientSessionGuard.configuration.modal_redirecting_text
    end
  end
end