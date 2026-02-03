require "json"

module App
  # Shared response types for OpenAPI generation

  # Health status for devices and provider
  record DeviceHealth, status : String, last_seen_at : Time? = nil do
    include JSON::Serializable
  end

  # Provider health response
  struct HealthResponse
    include JSON::Serializable

    getter status : String
    getter reasons : Array(String)?

    def initialize(@status : String, @reasons : Array(String)? = nil)
    end
  end

  # Device counts in provider info
  record DeviceCounts, devices : Int32, healthy : Int32, unhealthy : Int32 do
    include JSON::Serializable
  end

  # Provider info response (GET /)
  struct ProviderInfo
    include JSON::Serializable

    getter name : String
    getter version : String
    getter uptime_seconds : Int64
    getter device_types : Array(DeviceType)
    getter counts : DeviceCounts
    getter? commissioned : Bool
    getter fabrics : Int32

    def initialize(
      @name : String,
      @version : String,
      @uptime_seconds : Int64,
      @device_types : Array(DeviceType),
      @counts : DeviceCounts,
      @commissioned : Bool,
      @fabrics : Int32,
    )
    end
  end

  # Commission info (pairing details)
  struct CommissionInfo
    include JSON::Serializable

    getter qr_payload : String
    getter manual_pairing_code : String
    getter discriminator : UInt16
    getter expires_at : Time?

    def initialize(
      @qr_payload : String,
      @manual_pairing_code : String,
      @discriminator : UInt16,
      @expires_at : Time? = nil,
    )
    end
  end

  # Commission status response (GET /commission)
  struct CommissionStatus
    include JSON::Serializable

    getter? active : Bool
    getter? commissioned : Bool
    getter fabric_count : Int32
    getter commission_info : CommissionInfo?

    def initialize(
      @active : Bool,
      @commissioned : Bool,
      @fabric_count : Int32,
      @commission_info : CommissionInfo? = nil,
    )
    end
  end

  # Device types list response
  struct DeviceTypesResponse
    include JSON::Serializable

    getter device_types : Array(DeviceTypes::DeviceTypeInfo)

    def initialize(@device_types : Array(DeviceTypes::DeviceTypeInfo))
    end
  end

  # Device summary (for list)
  struct DeviceSummary
    include JSON::Serializable

    getter id : String
    getter type : DeviceType
    getter label : String
    getter health : DeviceHealth

    def initialize(@id : String, @type : DeviceType, @label : String, @health : DeviceHealth)
    end
  end

  # Device response (create/update)
  struct DeviceResponse
    include JSON::Serializable

    getter id : String
    getter type : DeviceType
    getter label : String
    getter settings : JSON::Any

    def initialize(@id : String, @type : DeviceType, @label : String, @settings : JSON::Any)
    end
  end

  # Device detail response (GET /devices/:id)
  struct DeviceDetail
    include JSON::Serializable

    getter id : String
    getter type : DeviceType
    getter label : String
    getter settings : JSON::Any
    getter health : DeviceHealth
    getter snapshot : JSON::Any
    getter endpoint : UInt16
    getter created_at : Time
    getter updated_at : Time

    def initialize(
      @id : String,
      @type : DeviceType,
      @label : String,
      @settings : JSON::Any,
      @health : DeviceHealth,
      @snapshot : JSON::Any,
      @endpoint : UInt16,
      @created_at : Time,
      @updated_at : Time,
    )
    end
  end

  # Device refresh response
  struct DeviceRefreshResponse
    include JSON::Serializable

    getter health : DeviceHealth
    getter snapshot : JSON::Any

    def initialize(@health : DeviceHealth, @snapshot : JSON::Any)
    end
  end

  # Delete response
  record DeleteResponse, deleted : Bool do
    include JSON::Serializable
  end

  # On/Off state response
  record OnOffResponse, on : Bool do
    include JSON::Serializable
  end

  # Level control response
  record LevelResponse, level : Int32, on : Bool do
    include JSON::Serializable
  end

  # API error response
  struct ErrorResponse
    include JSON::Serializable

    getter error : String
    getter message : String
    getter details : JSON::Any?

    def initialize(@error : String, @message : String, @details : JSON::Any? = nil)
    end
  end
end
