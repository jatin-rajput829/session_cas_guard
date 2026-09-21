# frozen_string_literal: true

require_relative "lib/cas_session_guard/version"

Gem::Specification.new do |spec|
  spec.name = "cas_session_guard"
  spec.version = CasSessionGuard::VERSION
  spec.authors = ["Jatin Rajput"]
  spec.email = ["hi.jatinrajput@gmail.com"]

  spec.summary = "CAS session validation, heartbeat, Sign Out support for Rails applications"
  spec.description = <<~DESCRIPTION
    Adds configurable CAS session validation, heartbeat support, Sign Out, Turbo/XHR
    expiration handling, and remote CAS ticket validation to Rails applications.
  DESCRIPTION
  spec.homepage = "https://github.com/MobsterLimited/cas_session_guard"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir[
    "README.md",
    "LICENSE",
    "CHANGELOG.md",
    "Gemfile",
    "Rakefile",
    "lib/**/*",
    "app/**/*",
    "config/**/*"
  ]

  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 6.1"
  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "httparty", ">= 0.20"
  spec.add_dependency "slim-rails"

  # Required only to develop and test the gem.
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", ">= 3.12"
  spec.add_development_dependency "rspec-rails", ">= 6.0"
  spec.add_development_dependency "webmock", ">= 3.18"

  spec.metadata["rubygems_mfa_required"] = "true"
end
