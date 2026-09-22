# frozen_string_literal: true

module CasinoClientSessionGuard
  module ApplicationHelper
    def render_cas_session_redirect_modal
      render "casino_client_session_guard/session_redirect_modal"
    end

    def cas_session_redirect_icon
      icon = CasinoClientSessionGuard.configuration.modal_icon

      return icon.call(self) if icon.respond_to?(:call)
      return icon.html_safe if icon.present?

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

    def cas_session_guard_meta_tags
      safe_join(
        [
          tag.meta(
            name: "cas-session-guard-token",
            content: session[CasinoClientSessionGuard.configuration.keep_alive_token_key].to_s
          ),
          tag.meta(
            name: "cas-session-guard-heartbeat-url",
            content: CasinoClientSessionGuard.configuration.heartbeat_path
          ),
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

    def cas_session_modal_title
      CasinoClientSessionGuard.configuration.modal_title
    end

    def cas_session_modal_message
      CasinoClientSessionGuard.configuration.modal_message
    end

    def cas_session_modal_detail
      CasinoClientSessionGuard.configuration.modal_detail
    end

    def cas_session_modal_countdown_seconds
      CasinoClientSessionGuard.configuration.modal_countdown_seconds
    end

    def cas_session_modal_redirecting_text
      CasinoClientSessionGuard.configuration.modal_redirecting_text
    end
  end
end