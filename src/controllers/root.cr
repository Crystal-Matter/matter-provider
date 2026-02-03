class App::Root < App::Base
  base "/"

  # OpenAPI spec generated at build time
  OPENAPI = YAML.parse(File.exists?("openapi.yml") ? File.read("openapi.yml") : "{}")

  # GET /openapi - Returns the OpenAPI specification
  @[AC::Route::GET("/openapi")]
  def openapi : YAML::Any
    OPENAPI
  end

  # GET / - Provider info
  @[AC::Route::GET("/")]
  def index : ProviderInfo
    provider.info
  end

  # GET /health - Health check
  @[AC::Route::GET("/health")]
  def health : HealthResponse
    health_info = provider.health
    if health_info.status == "ok"
      render json: health_info
    else
      render status: :service_unavailable, json: health_info
    end
  end

  # POST /commission - Open commissioning window for the bridge
  @[AC::Route::POST("/commission")]
  def commission(duration_seconds : Int32 = 900) : CommissionInfo
    provider.bridge.commission_info
  end

  # GET /commission - Get commissioning state for the bridge
  # Includes commission_info when commissioning is active (not yet commissioned)
  @[AC::Route::GET("/commission")]
  def commission_status : CommissionStatus
    active = !provider.bridge.commissioned?
    CommissionStatus.new(
      active: active,
      commissioned: provider.bridge.commissioned?,
      fabric_count: provider.bridge.fabric_count,
      commission_info: active ? provider.bridge.commission_info : nil
    )
  end
end
