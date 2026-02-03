require "uuid"
require "json"

module App
  # Custom exceptions for API error responses
  class Error < Exception
    getter error_code : String

    def initialize(@error_code : String, message : String)
      super(message)
    end
  end

  class NotFoundError < Error
    def initialize(message : String = "Resource not found")
      super("not_found", message)
    end
  end

  class BadRequestError < Error
    def initialize(message : String, @error_code : String = "bad_request")
      super(@error_code, message)
    end
  end

  class ValidationError < Error
    getter fields : Hash(String, String)

    def initialize(@fields : Hash(String, String))
      super("validation_failed", "invalid configuration")
    end
  end

  class InternalError < Error
    def initialize(message : String = "Internal server error")
      super("internal_error", message)
    end
  end
end

abstract class App::Base < ActionController::Base
  Log = ::App::Log.for("controller")

  @[AC::Route::Filter(:before_action)]
  def set_request_id
    request_id = UUID.random.to_s
    Log.context.set(
      client_ip: client_ip,
      request_id: request_id
    )
    response.headers["X-Request-ID"] = request_id
  end

  @[AC::Route::Filter(:before_action)]
  def check_bearer_auth
    return unless App.bearer_token

    auth_header = request.headers["Authorization"]?
    unless auth_header
      render status: :unauthorized, json: error_response("unauthorized", "Missing Authorization header")
      return
    end

    unless auth_header.starts_with?("Bearer ")
      render status: :unauthorized, json: error_response("unauthorized", "Invalid Authorization header format")
      return
    end

    token = auth_header[7..]
    unless token == App.bearer_token
      render status: :unauthorized, json: error_response("unauthorized", "Invalid bearer token")
      return
    end
  end

  # Exception handlers for custom errors
  @[AC::Route::Exception(App::NotFoundError, status_code: HTTP::Status::NOT_FOUND)]
  def not_found_error(error) : ErrorResponse
    ErrorResponse.new(error.error_code, error.message.as(String))
  end

  @[AC::Route::Exception(App::BadRequestError, status_code: HTTP::Status::BAD_REQUEST)]
  def bad_request_error(error) : ErrorResponse
    ErrorResponse.new(error.error_code, error.message.as(String))
  end

  @[AC::Route::Exception(App::ValidationError, status_code: HTTP::Status::UNPROCESSABLE_ENTITY)]
  def validation_error_handler(error) : NamedTuple(error: String, message: String, details: NamedTuple(fields: Hash(String, String)))
    {error: error.error_code, message: error.message.as(String), details: {fields: error.fields}}
  end

  @[AC::Route::Exception(App::InternalError, status_code: HTTP::Status::INTERNAL_SERVER_ERROR)]
  def internal_error(error) : ErrorResponse
    ErrorResponse.new(error.error_code, error.message.as(String))
  end

  @[AC::Route::Exception(AC::Route::NotAcceptable, status_code: HTTP::Status::NOT_ACCEPTABLE)]
  @[AC::Route::Exception(AC::Route::UnsupportedMediaType, status_code: HTTP::Status::UNSUPPORTED_MEDIA_TYPE)]
  def bad_media_type(error) : ErrorResponse
    ErrorResponse.new("media_type_error", error.message.as(String))
  end

  @[AC::Route::Exception(AC::Route::Param::MissingError, status_code: HTTP::Status::UNPROCESSABLE_ENTITY)]
  @[AC::Route::Exception(AC::Route::Param::ValueError, status_code: HTTP::Status::BAD_REQUEST)]
  def invalid_param(error) : NamedTuple(error: String, message: String, details: NamedTuple(parameter: String?, restriction: String?))
    {
      error:   "validation_failed",
      message: error.message.as(String),
      details: {
        parameter:   error.parameter,
        restriction: error.restriction,
      },
    }
  end

  @[AC::Route::Exception(JSON::ParseException, status_code: HTTP::Status::BAD_REQUEST)]
  def json_parse_error(error) : ErrorResponse
    ErrorResponse.new("invalid_json", error.message.as(String))
  end

  protected def error_response(code : String, message : String, details : Hash(String, String)? = nil)
    if details
      {error: code, message: message, details: details}
    else
      {error: code, message: message}
    end
  end

  protected def provider : App::Provider
    App::Provider.current
  end

  protected def registry : App::DeviceRegistry
    provider.registry
  end
end
