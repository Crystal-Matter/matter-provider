# Matter Provider Template

A template for building Matter device bridges for **Home Matters** - our Crystal-based home automation platform using the Matter protocol.

This provider template creates a Matter bridge that exposes virtual devices (on/off lights, dimmable lights) as Matter endpoints. Use it as a starting point for building providers that bridge real-world devices into the Matter ecosystem.

## What is a Provider?

A Provider is a standalone service that:

- Runs a **Matter bridge node** that can be commissioned into a Matter fabric (Apple Home, Google Home, etc.)
- Exposes an **Admin JSON API** for device management
- Maintains a **Device Registry** of bridged devices, each exposed as Matter endpoints
- Handles **persistence** of device configuration and Matter fabric credentials

See [PROVIDER_SPEC.md](PROVIDER_SPEC.md) for the full API specification.

## Quick Start

```bash
# Install dependencies
shards install

# Run in development
crystal run ./src/app.cr

# Run tests
crystal spec

# Build for production
crystal build ./src/app.cr -o matter-provider --release
```

### Command Line Options

```bash
./matter-provider --help
./matter-provider --http 0.0.0.0:8080     # Bind API to host:port
./matter-provider --data /var/lib/matter  # Storage directory
./matter-provider --bearer secret-token   # Enable API authentication
./matter-provider --routes                # List API routes
./matter-provider -d                      # Generate OpenAPI spec
```

## Adapting for Real Devices

This template uses virtual devices for demonstration. To connect real devices (smart ovens, thermostats, sensors, etc.), you'll need to modify several key areas:

### 1. Define Your Device Type

Add a new value to the `DeviceType` enum in `src/models/device_types.cr`:

```crystal
enum DeviceType
  OnOffLight
  DimmableLight
  SmartOven  # Add your new device type
end

# Define settings struct with connection parameters
struct SmartOvenSettings
  include JSON::Serializable

  @[JSON::Field(description: "IP address or hostname of the oven")]
  property host : String

  @[JSON::Field(description: "API port", minimum: 1, maximum: 65535)]
  property port : Int32 = 8080

  @[JSON::Field(description: "API authentication token", write_only: true)]
  property api_token : String?

  @[JSON::Field(description: "Polling interval in seconds", minimum: 1, maximum: 300)]
  property poll_interval : Int32 = 10
end
```

Update the `list`, `schema`, and `validate_settings` methods to include your new type.

### 2. Create Your Device Class

Create a new device model in `src/models/smart_oven_device.cr`:

```crystal
require "./bridged_device"
require "http/client"  # Or your device's protocol library

module App
  class SmartOvenDevice < BridgedDevice
    @[JSON::Field(key: "settings")]
    property settings : DeviceTypes::SmartOvenSettings

    # Connection state
    @[JSON::Field(ignore: true)]
    @client : HTTP::Client?

    @[JSON::Field(ignore: true)]
    @poll_fiber : Fiber?

    def initialize(id : String, label : String, @settings : DeviceTypes::SmartOvenSettings)
      super(id, DeviceType::SmartOven, label)
    end

    # Matter device type - use appropriate type for your device
    def matter_device_type : UInt32
      Matter::DeviceTypes::ON_OFF_PLUGIN_UNIT.to_u32  # Or appropriate type
    end

    # Define clusters for your device capabilities
    def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(@endpoint_id)

      # Add clusters based on device capabilities
      # e.g., OnOff for power, Temperature for sensors
      on_off = Matter::Cluster::OnOffCluster.new(endpoint)
      @on_off_cluster = on_off

      on_off.on_state_changed do |new_state|
        # Send command to real device
        send_power_command(new_state)
        touch
      end

      [on_off.as(Matter::Cluster::Base)]
    end

    # Implement actual device communication
    private def send_power_command(on : Bool) : Nil
      client = @client || return
      # Your device's API call here
      client.post("/api/power", body: {on: on}.to_json)
    rescue ex
      Log.error { "Failed to send command: #{ex.message}" }
      self.reachable = false
    end

    # Start polling for device state
    def start_polling : Nil
      @client = HTTP::Client.new(@settings.host, @settings.port)
      @poll_fiber = spawn do
        loop do
          poll_device_state
          sleep @settings.poll_interval.seconds
        end
      end
    end

    private def poll_device_state : Nil
      client = @client || return
      response = client.get("/api/status")
      if response.success?
        state = JSON.parse(response.body)
        # Update cluster state from device
        @on_off_cluster.try &.on = state["power"].as_bool
        self.reachable = true
        touch
      end
    rescue ex
      Log.error { "Poll failed: #{ex.message}" }
      self.reachable = false
    end

    # Required interface methods
    def on? : Bool
      @on_off_cluster.try(&.on_off?) || false
    end

    def on=(value : Bool) : Nil
      @on_off_cluster.try &.on = value
      send_power_command(value)
      touch
    end

    def toggle : Bool
      new_state = !on?
      self.on = new_state
      new_state
    end

    def snapshot : JSON::Any
      JSON.parse({
        on:        on?,
        reachable: reachable?,
      }.to_json)
    end

    def apply_settings(settings : JSON::Any) : Nil
      # Update settings, reconnect if needed
      if host = settings["host"]?.try(&.as_s?)
        @settings.host = host
        reconnect
      end
      touch
    end

    def settings_json : JSON::Any
      # Redact sensitive fields
      json = JSON.parse(@settings.to_json)
      if json["api_token"]?
        json.as_h["api_token"] = JSON::Any.new("***redacted***")
      end
      json
    end

    private def reconnect : Nil
      @client.try &.close
      @client = HTTP::Client.new(@settings.host, @settings.port)
    end
  end
end
```

### 3. Update the Device Registry

Modify `src/models/device_registry.cr` to handle your new device type in the `create` method:

```crystal
def create(type : DeviceType, label : String, settings : JSON::Any?) : BridgedDevice?
  # ... validation code ...

  device = case type
           in .on_off_light?   then OnOffDevice.new(id, label)
           in .dimmable_light? then DimmableDevice.new(id, label)
           in .smart_oven?     then SmartOvenDevice.new(id, label, parse_oven_settings(settings))
           end

  # ... rest of method ...
end
```

And update `deserialize_device` for loading persisted devices:

```crystal
private def deserialize_device(json : JSON::Any) : BridgedDevice?
  # ... type parsing ...

  case device_type
  in .on_off_light?   then OnOffDevice.from_json(json.to_json)
  in .dimmable_light? then DimmableDevice.from_json(json.to_json)
  in .smart_oven?     then SmartOvenDevice.from_json(json.to_json)
  end
end
```

### 4. Add Device Lifecycle Hooks

If your device needs to establish connections when added, update the registry's `on_device_added` callback or the bridge's `on_started` method:

```crystal
# In bridge_device.cr on_started or registry callback
device.start_polling if device.is_a?(SmartOvenDevice)
```

## Key Files Reference

| File | Purpose |
|------|---------|
| `src/models/device_types.cr` | Device type definitions and settings schemas |
| `src/models/bridged_device.cr` | Abstract base class for all bridged devices |
| `src/models/onoff_device.cr` | Example: Simple on/off device |
| `src/models/dimmable_device.cr` | Example: Dimmable device with level control |
| `src/models/device_registry.cr` | Device storage, creation, and endpoint assignment |
| `src/models/bridge_device.cr` | Matter bridge node configuration |
| `src/models/responses.cr` | API response types for OpenAPI generation |
| `src/controllers/devices.cr` | Device CRUD and control endpoints |
| `src/controllers/root.cr` | Health, commission, and OpenAPI endpoints |

## Matter Clusters

The Matter protocol uses clusters to define device capabilities. Common clusters for home devices:

| Cluster | Use Case |
|---------|----------|
| `OnOffCluster` | Power on/off control |
| `LevelControlCluster` | Brightness, volume, position |
| `ColorControlCluster` | RGB/HSV color control |
| `TemperatureMeasurementCluster` | Temperature sensors |
| `ThermostatCluster` | HVAC control |
| `DoorLockCluster` | Smart locks |
| `WindowCoveringCluster` | Blinds, shades, curtains |

See the [Matter specification](https://csa-iot.org/developer-resource/specifications-download-request/) for the full cluster library.

## Testing

```bash
# Run all specs
crystal spec

# Run specific spec file
crystal spec spec/devices_spec.cr

# Format code
crystal tool format

# Lint
./bin/ameba
```

## API Documentation

Generate OpenAPI specification:

```bash
./matter-provider -d -f openapi.yml
```

The spec is also available at runtime via `GET /openapi`.

## License

MIT
