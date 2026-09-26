# frozen_string_literal: true

require "rails_helper"
require "cgi"
require "rack/mock_request"

RSpec.describe CasinoClientSessionGuard::SingleLogoutMiddleware do
  before do
    configure_cas_session_guard
  end

  after do
    CasinoClientSessionGuard.reset_configuration!
  end

  it "is mounted in the host app middleware stack" do
    middleware_classes = Dummy::Application.middleware.map(&:klass)

    expect(middleware_classes).to include(CasinoClientSessionGuard::SingleLogoutMiddleware)
  end

  it "handles a CAS logoutRequest posted to an arbitrary service URL" do
    payload = <<~XML
      <samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
        <samlp:SessionIndex>ST-404</samlp:SessionIndex>
      </samlp:LogoutRequest>
    XML
    env = Rack::MockRequest.env_for(
      "/admin/sites/1play-uae/int/copy-of-1play-demo-v1-gb?locale=hu-HU",
      method: "POST",
      input: "logoutRequest=#{CGI.escape(payload)}",
      "CONTENT_TYPE" => "application/x-www-form-urlencoded"
    )

    status, = described_class.new(->(_env) { [404, { "Content-Type" => "text/plain" }, ["miss"]] }).call(env)

    expect(status).to eq(200)
    expect(
      CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-404")
    ).to be(true)
  end

  it "does not swallow unrelated missing POST routes" do
    env = Rack::MockRequest.env_for(
      "/missing_route",
      method: "POST",
      input: "anything=else",
      "CONTENT_TYPE" => "application/x-www-form-urlencoded"
    )
    status, = described_class.new(->(_env) { [404, { "Content-Type" => "text/plain" }, ["miss"]] }).call(env)

    expect(status).to eq(404)
  end

  it "passes through when single logout is disabled" do
    configure_cas_session_guard(single_logout_enabled: false)

    payload = <<~XML
      <samlp:LogoutRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol">
        <samlp:SessionIndex>ST-404</samlp:SessionIndex>
      </samlp:LogoutRequest>
    XML
    env = Rack::MockRequest.env_for(
      "/admin/sites/1play-uae/int/copy-of-1play-demo-v1-gb?locale=hu-HU",
      method: "POST",
      input: "logoutRequest=#{CGI.escape(payload)}",
      "CONTENT_TYPE" => "application/x-www-form-urlencoded"
    )

    status, = described_class.new(->(_env) { [404, { "Content-Type" => "text/plain" }, ["miss"]] }).call(env)

    expect(status).to eq(404)
    expect(
      CasinoClientSessionGuard.configuration.sign_out_store.invalidated?(ticket: "ST-404")
    ).to be(false)
  end
end
