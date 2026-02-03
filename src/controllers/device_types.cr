class App::DeviceTypesController < App::Base
  base "/device-types"

  # GET /device-types - List all device types
  @[AC::Route::GET("/")]
  def index : DeviceTypesResponse
    DeviceTypesResponse.new(DeviceTypes.list)
  end

  # GET /device-types/:type/schema - Get JSON schema for device type
  @[AC::Route::GET("/:type/schema")]
  def schema(type : String) : JSON::Any
    schema_data = DeviceTypes.schema(type)
    raise NotFoundError.new("Unknown device type: #{type}") unless schema_data

    schema_data
  end
end
