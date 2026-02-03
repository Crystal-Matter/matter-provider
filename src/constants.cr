require "action-controller/logger"

module App
  NAME = "matter-provider"
  {% begin %}
    VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
  {% end %}

  Log         = ::Log.for(NAME)
  LOG_BACKEND = ActionController.default_backend

  ENVIRONMENT   = ENV["SG_ENV"]? || "development"
  IS_PRODUCTION = ENVIRONMENT == "production"

  DEFAULT_PORT          = (ENV["SG_SERVER_PORT"]? || 3000).to_i
  DEFAULT_HOST          = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
  DEFAULT_PROCESS_COUNT = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

  STATIC_FILE_PATH = ENV["PUBLIC_WWW_PATH"]? || "./www"

  COOKIE_SESSION_KEY    = ENV["COOKIE_SESSION_KEY"]? || "_matter_provider_"
  COOKIE_SESSION_SECRET = ENV["COOKIE_SESSION_SECRET"]? || "4f74c0b358d5bab4000dd3c75465dc2c"

  # Provider-specific defaults
  DEFAULT_DATA_PATH = ENV["MATTER_DATA_PATH"]? || "."

  # Start time for uptime calculation
  class_property start_time : Time = Time.utc

  def self.running_in_production?
    IS_PRODUCTION
  end

  # flag to indicate if we're outputting trace logs
  class_getter? trace : Bool = false

  def self.register_severity_switch_signals : Nil
    {% unless flag?(:win32) %}
      Signal::USR1.trap do |signal|
        @@trace = !@@trace
        level = @@trace ? ::Log::Severity::Trace : (running_in_production? ? ::Log::Severity::Info : ::Log::Severity::Debug)
        puts " > Log level changed to #{level}"
        ::Log.builder.bind "#{NAME}.*", level, LOG_BACKEND

        signal.ignore
        register_severity_switch_signals
      end
    {% end %}
  end
end
