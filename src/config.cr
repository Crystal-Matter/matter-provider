# Application dependencies
require "json-schema"
require "action-controller"
require "yaml"
require "./constants"

# Matter protocol
require "matter"

# Application models
require "./models/responses"
require "./models/device_types"
require "./models/bridged_device"
require "./models/onoff_device"
require "./models/dimmable_device"
require "./models/device_registry"
require "./models/bridge_device"
require "./models/provider"

# Application code
require "./controllers/application"
require "./controllers/*"

# Server required after application controllers
require "action-controller/server"

module App
  # Bearer token for authentication (set via CLI)
  class_property bearer_token : String? = nil

  # Configure logging (backend defined in constants.cr)
  if running_in_production?
    log_level = ::Log::Severity::Info
    ::Log.setup "*", :warn, LOG_BACKEND
  else
    log_level = ::Log::Severity::Debug
    ::Log.setup "*", :info, LOG_BACKEND
  end
  ::Log.builder.bind "action-controller.*", log_level, LOG_BACKEND
  ::Log.builder.bind "#{NAME}.*", log_level, LOG_BACKEND

  # Filter out sensitive params that shouldn't be logged
  filter_params = ["password", "bearer_token"]
  keeps_headers = ["X-Request-ID"]

  # Add handlers that should run before your application
  ActionController::Server.before(
    ActionController::ErrorHandler.new(running_in_production?, keeps_headers),
    ActionController::LogHandler.new(filter_params),
    HTTP::CompressHandler.new
  )

  # Configure session cookies
  ActionController::Session.configure do |settings|
    settings.key = COOKIE_SESSION_KEY
    settings.secret = COOKIE_SESSION_SECRET
    settings.secure = running_in_production?
  end
end
