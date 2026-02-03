require "matter"
require "./device_registry"
require "./responses"

module App
  class BridgeDevice < Matter::Device::Base
    Log = ::App::Log.for("bridge")

    DEVICE_NAME = "Matter Provider Bridge"

    VENDOR_ID      = Matter::SetupPayload.test_vendor_id
    PRODUCT_ID     = rand(0x0001_u16..0xFFFF_u16)
    DISCRIMINATOR  = Matter::SetupPayload.generate_random_discriminator
    SETUP_PIN_CODE = Matter::SetupPayload.generate_random_pin

    BRIDGE_CONTEXT = ["bridge"] of String
    BRIDGE_KEY     = "bridge_config"

    getter registry : DeviceRegistry
    @storage_file : String

    def initialize(data_path : String)
      @storage_file = File.join(data_path, "matter_bridge_storage.json")
      @registry = DeviceRegistry.new(data_path)

      super(ip_addresses: local_ips)

      # Wire up registry callbacks
      @registry.on_device_added do |device|
        register_device_endpoint(device)
      end

      @registry.on_device_removed do |_id, endpoint_id|
        remove_endpoint(endpoint_id)
        Log.info { "Removed endpoint #{endpoint_id}" }
      end
    end

    def device_name : String
      DEVICE_NAME
    end

    def vendor_id : UInt16
      VENDOR_ID
    end

    def product_id : UInt16
      PRODUCT_ID
    end

    def discriminator : UInt16
      DISCRIMINATOR
    end

    def setup_pin : UInt32
      SETUP_PIN_CODE
    end

    def primary_device_type_id : UInt16
      Matter::DeviceTypes::ROOT_NODE
    end

    def vendor_name : String
      "Spider-Gazelle"
    end

    def product_name : String
      device_name
    end

    def product_appearance : Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct?
      Matter::Cluster::BasicInformationCluster::ProductAppearanceStruct.new(
        Matter::Cluster::BasicInformationCluster::ProductFinish::Matte
      )
    end

    protected def build_storage_manager : Matter::Storage::Manager
      Matter::Storage::Manager.new(Matter::Storage::JsonFileBackend.new(@storage_file))
    end

    protected def device_clusters : Array(Matter::Cluster::Base)
      [] of Matter::Cluster::Base
    end

    protected def endpoint_device_types : Hash(UInt16, UInt32)
      {} of UInt16 => UInt32
    end

    protected def on_started : Nil
      Log.info { "Matter bridge started" }
      Log.info { "Discriminator: #{discriminator}" }
      Log.info { "Setup PIN: #{setup_pin}" }

      # Load existing devices from registry
      if @registry.load
        Log.info { "Restoring #{@registry.size} devices from storage" }

        # Re-register all endpoints
        @registry.devices.each_value do |device|
          register_device_endpoint(device, notify: false)
        end

        # Restore cluster states after endpoints are created
        restore_cluster_states
      end
    end

    protected def on_shutdown : Nil
      Log.info { "Bridge shutdown complete" }
    end

    protected def started_commissioning_mode : Nil
      Log.info { "Bridge in Commissioning Mode" }
      Log.info { "mDNS: _matterc._udp.local" }
      Log.info { "Instance: #{responder.commissioning_instance_name || "<pending>"}" }
      Log.info { "Hostname: #{hostname}:#{port}" }

      manual_code = setup_code
      Log.info { "Pairing code: #{manual_code}" }
      Log.info { "chip-tool pairing code 1 #{manual_code}" }
    end

    protected def started_operational_mode : Nil
      Log.info { "Bridge in Operational Mode - commissioned and ready" }

      fabric_table.all_fabrics.each do |fabric|
        Log.info { "Fabric #{fabric.fabric_index}: 0x#{fabric.fabric_id.to_s(16).upcase}" }
      end
    end

    def setup_code : String
      Matter::SetupPayload.generate_manual_code(discriminator, setup_pin)
    end

    def qr_code_payload : String
      Matter::SetupPayload::QRCode.generate_qr_code(
        discriminator: discriminator,
        pin: setup_pin,
        vendor_id: vendor_id,
        product_id: product_id,
        flow: Matter::SetupPayload::QRCode::CommissionFlow::Standard,
        capabilities: Matter::SetupPayload::QRCode::DiscoveryCapability::BLE
      )
    end

    def commissioned? : Bool
      !fabric_table.empty?
    end

    def fabric_count : Int32
      fabric_table.size
    end

    def commission_info : CommissionInfo
      CommissionInfo.new(
        qr_payload: qr_code_payload,
        manual_pairing_code: setup_code,
        discriminator: discriminator,
        expires_at: nil
      )
    end

    private def register_device_endpoint(device : BridgedDevice, notify : Bool = true) : Bool
      success = add_endpoint(
        endpoint_id: device.endpoint_id,
        device_type: device.matter_device_type,
        clusters: device.clusters,
        notify_subscribers: notify
      )

      if success
        Log.info { "Registered endpoint #{device.endpoint_id} for device #{device.id}" }
      else
        Log.error { "Failed to register endpoint #{device.endpoint_id}" }
      end

      success
    end

    private def local_ips : Array(Socket::IPAddress)
      ips = [] of Socket::IPAddress

      begin
        socket = UDPSocket.new(:inet6)
        socket.connect("2606:4700:4700::1111", 53)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
      end

      begin
        socket = UDPSocket.new(:inet)
        socket.connect("8.8.8.8", 80)
        addr = socket.local_address
        socket.close
        ips << Socket::IPAddress.new(addr.address, 0)
      rescue
      end

      ips << Socket::IPAddress.new("127.0.0.1", 0) if ips.empty?
      ips
    end
  end
end
