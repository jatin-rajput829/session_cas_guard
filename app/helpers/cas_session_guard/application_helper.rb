# frozen_string_literal: true

module CasSessionGuard
  module ApplicationHelper
    def render_cas_session_redirect_modal
      render "cas_session_guard/session_redirect_modal"
    end

    def cas_session_redirect_icon
      icon = CasSessionGuard.configuration.modal_icon

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
            content: session[CasSessionGuard.configuration.keep_alive_token_key].to_s
          ),
          tag.meta(
            name: "cas-session-guard-heartbeat-url",
            content: CasSessionGuard.configuration.heartbeat_path
          ),
          tag.meta(
            name: "cas-session-guard-heartbeat-interval",
            content: (
              CasSessionGuard.configuration.heartbeat_interval.to_f * 1000
            ).to_i
          )
        ],
        "\n"
      )
    end

    def cas_session_modal_title
      CasSessionGuard.configuration.modal_title
    end

    def cas_session_modal_message
      CasSessionGuard.configuration.modal_message
    end

    def cas_session_modal_detail
      CasSessionGuard.configuration.modal_detail
    end

    def cas_session_modal_countdown_seconds
      CasSessionGuard.configuration.modal_countdown_seconds
    end

    def cas_session_modal_redirecting_text
      CasSessionGuard.configuration.modal_redirecting_text
    end
  end
end