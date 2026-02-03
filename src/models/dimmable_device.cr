require "./bridged_device"

module App
  class DimmableDevice < BridgedDevice
    @[JSON::Field(key: "settings")]
    property settings : DeviceTypes::DimmableSettings

    @[JSON::Field(ignore: true)]
    @on_off_cluster : Matter::Cluster::OnOffCluster? = nil

    @[JSON::Field(ignore: true)]
    @level_control_cluster : Matter::Cluster::LevelControlCluster? = nil

    def initialize(id : String, label : String, @settings : DeviceTypes::DimmableSettings = DeviceTypes::DimmableSettings.new)
      super(id, DeviceType::DimmableLight, label)
    end

    def on? : Bool
      @on_off_cluster.try(&.on_off?) || @settings.initial_state?
    end

    def on=(value : Bool) : Nil
      @on_off_cluster.try &.on = value
      touch
    end

    def toggle : Bool
      if cluster = @on_off_cluster
        cluster.toggle
        touch
        cluster.on_off?
      else
        !@settings.initial_state?
      end
    end

    def level : UInt8
      @level_control_cluster.try(&.current_level) || percent_to_level(@settings.initial_level)
    end

    def level=(percent : Int32) : Nil
      @level_control_cluster.try do |cluster|
        cluster.level = percent.to_f
        touch
      end
    end

    def level_percent : Int32
      (level.to_i * 100) // 254
    end

    def matter_device_type : UInt32
      Matter::DeviceTypes::DIMMABLE_LIGHT.to_u32
    end

    def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(@endpoint_id)

      min_level_raw = percent_to_level(@settings.min_level)
      max_level_raw = percent_to_level(@settings.max_level)
      initial_level_raw = percent_to_level(@settings.initial_level)

      on_off = Matter::Cluster::OnOffCluster.new(
        endpoint,
        feature_map: Matter::Cluster::OnOffCluster::Feature::Lighting
      )
      @on_off_cluster = on_off

      level_control = Matter::Cluster::LevelControlCluster.new(
        endpoint,
        current_level: initial_level_raw,
        min_level: min_level_raw,
        max_level: max_level_raw,
        feature_map: Matter::Cluster::LevelControlCluster::Feature::OnOff |
                     Matter::Cluster::LevelControlCluster::Feature::Lighting
      )
      @level_control_cluster = level_control

      # Set initial state
      on_off.on = @settings.initial_state?

      # Wire up callbacks
      on_off.on_state_changed { |_| touch }

      level_control.on_level_changed do |_old_level, new_level|
        # Sync level with on/off state (Apple Home behavior)
        if new_level <= level_control.min_level
          on_off.on = false if on_off.on?
        elsif on_off.off?
          on_off.on = true
        end
        touch
      end

      [
        on_off.as(Matter::Cluster::Base),
        level_control.as(Matter::Cluster::Base),
      ] of Matter::Cluster::Base
    end

    def on_off_cluster : Matter::Cluster::OnOffCluster?
      @on_off_cluster
    end

    def level_control_cluster : Matter::Cluster::LevelControlCluster?
      @level_control_cluster
    end

    def snapshot : JSON::Any
      JSON.parse({
        on:        on?,
        level:     level_percent,
        level_raw: level.to_i,
        reachable: reachable?,
      }.to_json)
    end

    def apply_settings(settings : JSON::Any) : Nil
      if initial = settings["initial_state"]?.try(&.as_bool?)
        @settings.initial_state = initial
      end
      if level = settings["initial_level"]?.try(&.as_i?)
        @settings.initial_level = level
      end
      if min = settings["min_level"]?.try(&.as_i?)
        @settings.min_level = min
      end
      if max = settings["max_level"]?.try(&.as_i?)
        @settings.max_level = max
      end
      if name = settings["name"]?.try(&.as_s?)
        @settings.name = name
      end
      touch
    end

    def settings_json : JSON::Any
      JSON.parse(@settings.to_json)
    end

    private def percent_to_level(percent : Int32) : UInt8
      ((percent.clamp(0, 100) * 254) // 100).to_u8
    end
  end
end
