# frozen_string_literal: true

module CasinoClientSessionGuard
  class SingleLogoutsController < ActionController::Base
    protect_from_forgery with: :null_session

    def create
      return head :not_found unless CasinoClientSessionGuard.configuration.single_logout_enabled

      return head :bad_request unless logout_request.invalidate!

      head :ok
    rescue REXML::ParseException => error
      Rails.logger.warn(
        "[CasinoClientSessionGuard] single logout payload parse failed: " \
        "#{error.class}: #{error.message}"
      )
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
  end
end
