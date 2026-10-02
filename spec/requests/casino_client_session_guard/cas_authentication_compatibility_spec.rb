# frozen_string_literal: true

require "rails_helper"

class TestCasProtectedController < ActionController::Base
  include CasinoClientSessionGuard::Protectable

  def index
    render json: {
      cas_user: session[CasinoClientSessionGuard.configuration.cas_user_key],
      cas_ticket: session[CasinoClientSessionGuard.configuration.cas_ticket_key],
      cas_service_url: session[CasinoClientSessionGuard.configuration.cas_service_url_key],
      cas_extra_attributes: session[CasinoClientSessionGuard.configuration.cas_extra_attributes_key]
    }
  end
end

RSpec.describe "CAS authentication compatibility", type: :request do
  around do |example|
    Rails.application.routes.draw do
      get "/protected", to: "test_cas_protected#index"
      mount CasinoClientSessionGuard::Engine => "/cas_session_guard"
    end

    example.run
  ensure
    Rails.application.routes.draw do
      mount CasinoClientSessionGuard::Engine => "/cas_session_guard"
    end
  end

  before do
    configure_cas_session_guard
  end

  it "authenticates a request from standard namespaced CAS serviceValidate XML" do
    CasinoClientSessionGuard.configuration.cas_validate_url = "https://cas.example.com/serviceValidate"

    WebMock.stub_request(:get, "https://cas.example.com/serviceValidate")
      .with(query: { service: "http://www.example.com/protected", ticket: "ST-123" })
      .to_return(
        status: 200,
        body: <<~XML,
          <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
            <cas:authenticationSuccess>
              <cas:user>admin@example.com</cas:user>
              <cas:attributes>
                <cas:role>admin</cas:role>
              </cas:attributes>
            </cas:authenticationSuccess>
          </cas:serviceResponse>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    get "/protected", params: { ticket: "ST-123" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      "cas_user" => "admin@example.com",
      "cas_ticket" => "ST-123",
      "cas_service_url" => "http://www.example.com/protected",
      "cas_extra_attributes" => { "role" => "admin" }.to_json
    )
  end

  it "authenticates a request from namespace-free CAS serviceValidate XML" do
    CasinoClientSessionGuard.configuration.cas_validate_url = "https://cas.example.com/serviceValidate"

    WebMock.stub_request(:get, "https://cas.example.com/serviceValidate")
      .with(query: { service: "http://www.example.com/protected", ticket: "ST-456" })
      .to_return(
        status: 200,
        body: <<~XML,
          <serviceResponse>
            <authenticationSuccess>
              <user>reporter@example.com</user>
              <attributes>
                <department>ops</department>
              </attributes>
            </authenticationSuccess>
          </serviceResponse>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    get "/protected", params: { ticket: "ST-456" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      "cas_user" => "reporter@example.com",
      "cas_ticket" => "ST-456",
      "cas_service_url" => "http://www.example.com/protected",
      "cas_extra_attributes" => { "department" => "ops" }.to_json
    )
  end

  it "redirects back to CAS login when the CAS server returns an authentication failure XML" do
    CasinoClientSessionGuard.configuration.cas_validate_url = "https://cas.example.com/serviceValidate"

    WebMock.stub_request(:get, "https://cas.example.com/serviceValidate")
      .with(query: { service: "http://www.example.com/protected", ticket: "ST-789" })
      .to_return(
        status: 200,
        body: <<~XML,
          <serviceResponse>
            <authenticationFailure code="INVALID_TICKET">bad ticket</authenticationFailure>
          </serviceResponse>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    get "/protected", params: { ticket: "ST-789" }

    expect(response).to redirect_to(
      "https://cas.example.com/login?service=http%3A%2F%2Fwww.example.com%2Fprotected"
    )
  end

  it "matches the old rubycas-client proxyValidate behavior for the provided CAS response" do
    WebMock.stub_request(:get, "https://cas.example.com/proxyValidate")
      .with(query: { service: "http://www.example.com/protected?locale=en", ticket: "ST-999" })
      .to_return(
        status: 200,
        body: <<~XML,
          <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
            <cas:authenticationSuccess>
              <cas:user>user@contentformobile.net</cas:user>
              <cas:attributes>
                <cas:authenticationDate>2026-10-02T07:56:26Z</cas:authenticationDate>
                <cas:longTermAuthenticationRequestTokenUsed>false</cas:longTermAuthenticationRequestTokenUsed>
                <cas:isFromNewLogin>false</cas:isFromNewLogin>
                <cas:roles>developer</cas:roles>
              </cas:attributes>
            </cas:authenticationSuccess>
          </cas:serviceResponse>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    get "/protected", params: { locale: "en", ticket: "ST-999" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      "cas_user" => "user@contentformobile.net",
      "cas_ticket" => "ST-999",
      "cas_service_url" => "http://www.example.com/protected?locale=en",
      "cas_extra_attributes" => {
        "authenticationDate" => "2026-10-02T07:56:26Z",
        "longTermAuthenticationRequestTokenUsed" => false,
        "isFromNewLogin" => false,
        "roles" => "developer"
      }.to_json
    )
  end
end