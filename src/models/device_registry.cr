require "json"
require "./device_types"
require "./bridged_device"
require "./onoff_device"
require "./dimmable_device"

module App
  class DeviceRegistry
    Log = ::App::Log.for("device_registry")

    # Persisted state
    struct PersistedState
      include JSON::Serializable

      property devices : Array(JSON::Any)
      property endpoint_map : Hash(String, UInt16)
      property next_endpoint : UInt16
      property device_counter : Int32

      def initialize(
        @devices = [] of JSON::Any,
        @endpoint_map = {} of String => UInt16,
        @next_endpoint = 1_u16,
        @device_counter = 0,
      )
      end
    end

    getter devices : Hash(String, BridgedDevice) = {} of String => BridgedDevice
    @endpoint_map : Hash(String, UInt16) = {} of String => UInt16
    @next_endpoint : UInt16 = 1_u16
    @device_counter : Int32 = 0
    @storage_path : String
    @on_device_added : Proc(BridgedDevice, Nil)?
    @on_device_removed : Proc(String, UInt16, Nil)?

    def initialize(@storage_path : String)
    end

    def on_device_added(&block : BridgedDevice -> Nil) : Nil
      @on_device_added = block
    end

    def on_device_removed(&block : String, UInt16 -> Nil) : Nil
      @on_device_removed = block
    end

    def load : Bool
      path = File.join(@storage_path, "devices.json")
      return false unless File.exists?(path)

      json = File.read(path)
      state = PersistedState.from_json(json)

      @endpoint_map = state.endpoint_map
      @next_endpoint = state.next_endpoint
      @device_counter = state.device_counter

      state.devices.each do |device_json|
        device = deserialize_device(device_json)
        next unless device

        # Restore endpoint mapping
        if endpoint_id = @endpoint_map[device.id]?
          device.endpoint_id = endpoint_id
        end

        @devices[device.id] = device
      end

      Log.info { "Loaded #{@devices.size} devices from storage" }
      true
    rescue ex
      Log.error(exception: ex) { "Failed to load devices" }
      false
    end

    def save : Nil
      Dir.mkdir_p(@storage_path) unless Dir.exists?(@storage_path)

      state = PersistedState.new(
        devices: @devices.values.map { |device| serialize_device(device) },
        endpoint_map: @endpoint_map,
        next_endpoint: @next_endpoint,
        device_counter: @device_counter
      )

      path = File.join(@storage_path, "devices.json")
      File.write(path, state.to_json)
      Log.debug { "Saved #{@devices.size} devices to storage" }
    rescue ex
      Log.error(exception: ex) { "Failed to save devices" }
    end

    def create(type : String, label : String, settings : JSON::Any?) : BridgedDevice?
      device_type = DeviceType.parse?(type)
      return nil unless device_type

      create(device_type, label, settings)
    end

    def create(type : DeviceType, label : String, settings : JSON::Any?) : BridgedDevice?
      # Validate settings if provided
      if settings
        errors = DeviceTypes.validate_settings(type, settings)
        if errors && !errors.empty?
          Log.warn { "Invalid settings: #{errors}" }
          return nil
        end
      end

      @device_counter += 1
      id = "dev-#{Random::Secure.hex(8)}"
      endpoint_id = allocate_endpoint(id)

      device = case type
               in .on_off_light?   then OnOffDevice.new(id, label)
               in .dimmable_light? then DimmableDevice.new(id, label)
               end

      device.endpoint_id = endpoint_id

      # Apply settings if provided
      if settings
        device.apply_settings(settings)
      end

      @devices[id] = device
      save

      # Notify bridge to add endpoint
      @on_device_added.try &.call(device)

      Log.info { "Created device #{id} (#{type}) on endpoint #{endpoint_id}" }
      device
    end

    def get(id : String) : BridgedDevice?
      @devices[id]?
    end

    def update(id : String, label : String? = nil, settings : JSON::Any? = nil) : BridgedDevice?
      device = @devices[id]?
      return nil unless device

      if label
        device.label = label
      end

      if settings
        errors = DeviceTypes.validate_settings(device.type, settings)
        if errors && !errors.empty?
          Log.warn { "Invalid settings for update: #{errors}" }
          return nil
        end
        device.apply_settings(settings)
      end

      device.updated_at = Time.utc
      save

      Log.info { "Updated device #{id}" }
      device
    end

    def delete(id : String) : Bool
      device = @devices.delete(id)
      return false unless device

      endpoint_id = @endpoint_map.delete(id)
      save

      # Notify bridge to remove endpoint
      if endpoint_id
        @on_device_removed.try &.call(id, endpoint_id)
      end

      Log.info { "Deleted device #{id}" }
      true
    end

    def list : Array(BridgedDevice)
      @devices.values
    end

    def size : Int32
      @devices.size
    end

    def healthy_count : Int32
      @devices.values.count(&.reachable?)
    end

    def unhealthy_count : Int32
      @devices.values.count { |device| !device.reachable? }
    end

    def endpoint_for(id : String) : UInt16?
      @endpoint_map[id]?
    end

    def device_for_endpoint(endpoint_id : UInt16) : BridgedDevice?
      @endpoint_map.each do |device_id, endpoint|
        return @devices[device_id]? if endpoint == endpoint_id
      end
      nil
    end

    private def allocate_endpoint(id : String) : UInt16
      endpoint_id = @next_endpoint
      @endpoint_map[id] = endpoint_id
      @next_endpoint += 1
      endpoint_id
    end

    private def serialize_device(device : BridgedDevice) : JSON::Any
      JSON.parse(device.to_json)
    end

    private def deserialize_device(json : JSON::Any) : BridgedDevice?
      type_str = json["type"]?.try(&.as_s?)
      return nil unless type_str

      device_type = DeviceType.parse?(type_str)
      return nil unless device_type

      case device_type
      in .on_off_light?   then OnOffDevice.from_json(json.to_json)
      in .dimmable_light? then DimmableDevice.from_json(json.to_json)
      end
    rescue ex
      Log.error(exception: ex) { "Failed to deserialize device" }
      nil
    end
  end
end
