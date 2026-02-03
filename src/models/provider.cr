require "./bridge_device"
require "./device_registry"
require "./device_types"
require "./responses"

module App
  class Provider
    Log = ::App::Log.for("provider")

    class_property instance : Provider?

    getter bridge : BridgeDevice
    getter data_path : String
    @started_at : Time

    def initialize(@data_path : String)
      @bridge = BridgeDevice.new(@data_path)
      @started_at = Time.utc
      @@instance = self
    end

    def self.current : Provider
      @@instance.as(Provider)
    end

    def self.current? : Provider?
      @@instance
    end

    def start : Nil
      Log.info { "Starting provider with data path: #{@data_path}" }
      spawn { @bridge.start }
    end

    def stop : Nil
      @bridge.shutdown!
    end

    def registry : DeviceRegistry
      @bridge.registry
    end

    def uptime_seconds : Int64
      (Time.utc - @started_at).total_seconds.to_i64
    end

    def info : ProviderInfo
      ProviderInfo.new(
        name: App::NAME,
        version: App::VERSION,
        uptime_seconds: uptime_seconds,
        device_types: DeviceType.values,
        counts: DeviceCounts.new(
          devices: registry.size,
          healthy: registry.healthy_count,
          unhealthy: registry.unhealthy_count
        ),
        commissioned: @bridge.commissioned?,
        fabrics: @bridge.fabric_count
      )
    end

    def health : HealthResponse
      reasons = [] of String

      registry.devices.each_value do |device|
        unless device.reachable?
          reasons << "device:#{device.id} unreachable"
        end
      end

      status = reasons.empty? ? "ok" : "degraded"
      HealthResponse.new(status, reasons.empty? ? nil : reasons)
    end
  end
end
