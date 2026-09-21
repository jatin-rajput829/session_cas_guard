# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "rspec/rails"

require_relative "dummy/config/application"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
