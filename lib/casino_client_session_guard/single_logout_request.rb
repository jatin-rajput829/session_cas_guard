# frozen_string_literal: true

require "rexml/document"

module CasinoClientSessionGuard
  class SingleLogoutRequest
    attr_reader :ticket_param, :logout_request_param, :raw_payload, :media_type

    def initialize(ticket_param:, logout_request_param:, raw_payload:, media_type: nil)
      @ticket_param = ticket_param
      @logout_request_param = logout_request_param
      @raw_payload = raw_payload
      @media_type = media_type
    end

    def tickets
      @tickets ||= (direct_tickets + xml_tickets).uniq
    end

    def invalidate!(store: configuration.sign_out_store, ttl: configuration.sign_out_ttl)
      return false if tickets.empty?
      return false unless store.respond_to?(:invalidate)

      tickets.each do |ticket|
        store.invalidate(ticket: ticket, ttl: ttl)
      end

      true
    end

    private

    def configuration
      CasinoClientSessionGuard.configuration
    end

    def direct_tickets
      ticket = ticket_param.to_s.strip
      ticket.present? ? [ticket] : []
    end

    def xml_tickets
      payload = xml_payload
      return [] if payload.blank?

      document = REXML::Document.new(payload)
      find_session_indices(document.root).map { |element| element.text.to_s.strip }.reject(&:blank?).uniq
    end

    def xml_payload
      return logout_request_param if logout_request_param.present?

      raw_xml = raw_payload.to_s
      return if raw_xml.blank?
      return raw_xml if media_type.to_s.include?("xml")
      return raw_xml if raw_xml.lstrip.start_with?("<")

      nil
    end

    def find_session_indices(node, matches = [])
      return matches if node.nil?

      matches << node if node.name.to_s.split(":").last == "SessionIndex"

      node.elements.each do |child|
        find_session_indices(child, matches)
      end

      matches
    end
  end
end
