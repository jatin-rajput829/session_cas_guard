# frozen_string_literal: true

module CasinoClientSessionGuard
  class SingleLogoutsController < ActionController::Base
    protect_from_forgery with: :null_session

    def create
      unless CasinoClientSessionGuard.configuration.single_logout_enabled
        instrument_single_logout("disabled", ticket_count: 0)
        return head :not_found
      end

      unless logout_request.invalidate!
        instrument_single_logout("bad_request", ticket_count: 0)
        return head :bad_request
      end

      instrument_single_logout("processed", ticket_count: logout_request.tickets.size)

      head :ok
    rescue REXML::ParseException => error
      Rails.logger.warn(
        "[CasinoClientSessionGuard] single logout payload parse failed: " \
        "#{error.class}: #{error.message}"
      )
      instrument_single_logout("bad_request", ticket_count: 0, error_class: error.class.name)
      head :bad_request
    end

    private

    def logout_request
      @logout_request ||= CasinoClientSessionGuard::SingleLogoutRequest.new(
        ticket_param: params[:ticket],
        logout_request_param: params[:logoutRequest],
        raw_payload: request.raw_post,
        media_type: request.media_type
      )
    end

    def instrument_single_logout(outcome, ticket_count:, error_class: nil)
      CasinoClientSessionGuard::Observability.instrument(
        "single_logout",
        outcome: outcome,
        ticket_count: ticket_count,
        error_class: error_class,
        source: "controller"
      )
    end
  end
end
