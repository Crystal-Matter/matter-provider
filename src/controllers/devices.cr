class App::DevicesController < App::Base
  base "/devices"

  # GET /devices - List all devices
  @[AC::Route::GET("/")]
  def index : Array(DeviceSummary)
    registry.list.map(&.to_summary)
  end

  # POST /devices - Create a new device
  @[AC::Route::POST("/", body: :create_params, status_code: HTTP::Status::CREATED)]
  def create(create_params : CreateDeviceRequest) : DeviceResponse
    raise BadRequestError.new("Unknown device type: #{create_params.type}", "invalid_type") unless DeviceTypes.valid?(create_params.type)

    # Validate settings if provided
    if settings = create_params.settings
      if errors = DeviceTypes.validate_settings(create_params.type, settings)
        raise ValidationError.new(errors) unless errors.empty?
      end
    end

    device = registry.create(create_params.type, create_params.label, create_params.settings)
    raise InternalError.new("Failed to create device") unless device

    device_response(device)
  end

  # GET /devices/:id - Get device details
  @[AC::Route::GET("/:id")]
  def show(id : String) : DeviceDetail
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    device_detail_response(device)
  end

  # PATCH /devices/:id - Update device
  @[AC::Route::PATCH("/:id", body: :update_params)]
  def update(id : String, update_params : UpdateDeviceRequest) : DeviceResponse
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    # Validate settings if provided
    if settings = update_params.settings
      if errors = DeviceTypes.validate_settings(device.type, settings)
        raise ValidationError.new(errors) unless errors.empty?
      end
    end

    updated = registry.update(id, update_params.label, update_params.settings)
    raise InternalError.new("Failed to update device") unless updated

    device_response(updated)
  end

  # DELETE /devices/:id - Delete device
  @[AC::Route::DELETE("/:id")]
  def delete(id : String) : DeleteResponse
    raise NotFoundError.new("Device not found: #{id}") unless registry.get(id)
    raise InternalError.new("Failed to delete device") unless registry.delete(id)

    DeleteResponse.new(true)
  end

  # POST /devices/:id/refresh - Trigger device refresh
  @[AC::Route::POST("/:id/refresh")]
  def refresh(id : String) : DeviceRefreshResponse
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    device.touch
    DeviceRefreshResponse.new(device.health, device.snapshot)
  end

  # GET /devices/:id/state - Get device state (for testing)
  @[AC::Route::GET("/:id/state")]
  def state(id : String) : JSON::Any
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    device.snapshot
  end

  # POST /devices/:id/on - Turn device on
  @[AC::Route::POST("/:id/on")]
  def turn_on(id : String) : OnOffResponse
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    device.on = true
    OnOffResponse.new(device.on?)
  end

  # POST /devices/:id/off - Turn device off
  @[AC::Route::POST("/:id/off")]
  def turn_off(id : String) : OnOffResponse
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    device.on = false
    OnOffResponse.new(device.on?)
  end

  # POST /devices/:id/toggle - Toggle device state
  @[AC::Route::POST("/:id/toggle")]
  def toggle(id : String) : OnOffResponse
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device

    new_state = device.toggle
    OnOffResponse.new(new_state)
  end

  # POST /devices/:id/level - Set dimmable device level
  @[AC::Route::POST("/:id/level", body: :level_params)]
  def set_level(id : String, level_params : SetLevelRequest) : LevelResponse
    device = registry.get(id)
    raise NotFoundError.new("Device not found: #{id}") unless device
    raise BadRequestError.new("Device does not support level control", "invalid_device_type") unless device.is_a?(DimmableDevice)

    device.level = level_params.level
    LevelResponse.new(device.level_percent, device.on?)
  end

  private def device_response(device : BridgedDevice) : DeviceResponse
    DeviceResponse.new(device.id, device.type, device.label, device.settings_json)
  end

  private def device_detail_response(device : BridgedDevice) : DeviceDetail
    DeviceDetail.new(
      id: device.id,
      type: device.type,
      label: device.label,
      settings: device.settings_json,
      health: device.health,
      snapshot: device.snapshot,
      endpoint: device.endpoint_id,
      created_at: device.created_at,
      updated_at: device.updated_at
    )
  end

  struct CreateDeviceRequest
    include JSON::Serializable

    property type : String
    property label : String
    property settings : JSON::Any?
  end

  struct UpdateDeviceRequest
    include JSON::Serializable

    property label : String?
    property settings : JSON::Any?
  end

  struct SetLevelRequest
    include JSON::Serializable

    property level : Int32
  end
end
