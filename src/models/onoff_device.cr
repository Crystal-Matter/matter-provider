require "./bridged_device"

module App
  class OnOffDevice < BridgedDevice
    @[JSON::Field(key: "settings")]
    property settings : DeviceTypes::OnOffSettings

    @[JSON::Field(ignore: true)]
    @on_off_cluster : Matter::Cluster::OnOffCluster? = nil

    def initialize(id : String, label : String, @settings : DeviceTypes::OnOffSettings = DeviceTypes::OnOffSettings.new)
      super(id, DeviceType::OnOffLight, label)
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

    def matter_device_type : UInt32
      Matter::DeviceTypes::ON_OFF_LIGHT.to_u32
    end

    def device_clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(@endpoint_id)

      on_off = Matter::Cluster::OnOffCluster.new(
        endpoint,
        feature_map: Matter::Cluster::OnOffCluster::Feature::None
      )
      @on_off_cluster = on_off

      # Set initial state
      on_off.on = @settings.initial_state?

      # Wire up state change callback
      on_off.on_state_changed do |_new_state|
        touch
      end

      [
        on_off.as(Matter::Cluster::Base),
      ] of Matter::Cluster::Base
    end

    def on_off_cluster : Matter::Cluster::OnOffCluster?
      @on_off_cluster
    end

    def snapshot : JSON::Any
      JSON.parse({
        on:        on?,
        reachable: reachable?,
      }.to_json)
    end

    def apply_settings(settings : JSON::Any) : Nil
      if initial = settings["initial_state"]?.try(&.as_bool?)
        @settings.initial_state = initial
      end
      if name = settings["name"]?.try(&.as_s?)
        @settings.name = name
      end
      touch
    end

    def settings_json : JSON::Any
      JSON.parse(@settings.to_json)
    end
  end
end
