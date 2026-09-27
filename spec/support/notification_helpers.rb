# frozen_string_literal: true

module NotificationHelpers
  def capture_notifications(event_name)
    events = []
    callback = lambda do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    ActiveSupport::Notifications.subscribed(
      callback,
      CasinoClientSessionGuard::Observability.notification_name(event_name)
    ) do
      yield
    end

    events
  end
end

RSpec.configure do |config|
  config.include NotificationHelpers
end
