require "json"
require "matter"
require "./responses"

module App
  abstract class BridgedDevice
    include JSON::Serializable
    include JSON::Serializable::Strict

    getter id : String
    getter type : DeviceType
    property label : String { type.to_s.underscore.gsub('_', ' ').titleize }
    getter created_at : Time
    property updated_at : Time

    @[JSON::Field(ignore: true)]
    property endpoint_id : UInt16 = 0_u16

    @[JSON::Field(ignore: true)]
    property? reachable : Bool = true

    @[JSON::Field(ignore: true)]
    @bridged_info_cluster : Matter::Cluster::BridgedDeviceBasicInformationCluster? = nil

    @[JSON::Field(ignore: true)]
    @identify_cluster : Matter::Cluster::IdentifyCluster? = nil

    def initialize(@id : String, @type : DeviceType, @label : String)
      @created_at = Time.utc
      @updated_at = Time.utc
    end

    abstract def on? : Bool
    abstract def on=(value : Bool)
    abstract def toggle : Bool
    abstract def matter_device_type : UInt32
    abstract def device_clusters : Array(Matter::Cluster::Base)
    abstract def snapshot : JSON::Any
    abstract def apply_settings(settings : JSON::Any) : Nil
    abstract def settings_json : JSON::Any

    def clusters : Array(Matter::Cluster::Base)
      endpoint = Matter::DataType::EndpointNumber.new(@endpoint_id)

      bridged_info = Matter::Cluster::BridgedDeviceBasicInformationCluster.new(
        endpoint,
        reachable: @reachable,
        vendor_name: "Matter Provider",
        product_name: @label,
        node_label: @label,
        unique_id: @id,
        hardware_version: 1_u16,
        hardware_version_string: "1.0",
        software_version: 1_u32,
        software_version_string: "1.0.0"
      )
      @bridged_info_cluster = bridged_info

      bridged_info.on_reachable_changed = ->(new_state : Bool) {
        @reachable = new_state
        nil
      }

      identify = Matter::Cluster::IdentifyCluster.new(
        endpoint,
        identify_type: Matter::Cluster::IdentifyCluster::IdentifyType::VisibleLight
      )
      @identify_cluster = identify

      result = [
        bridged_info.as(Matter::Cluster::Base),
        identify.as(Matter::Cluster::Base),
      ]
      result.concat(device_clusters)
      result
    end

    def bridged_info_cluster : Matter::Cluster::BridgedDeviceBasicInformationCluster?
      @bridged_info_cluster
    end

    def reachable=(value : Bool) : Nil
      @reachable = value
      @bridged_info_cluster.try &.reachable = value
    end

    def health : DeviceHealth
      status = @reachable ? "ok" : "unreachable"
      DeviceHealth.new(status, @updated_at)
    end

    def to_summary : DeviceSummary
      DeviceSummary.new(@id, @type, label, health)
    end

    def touch : Nil
      @updated_at = Time.utc
    end
  end
end
