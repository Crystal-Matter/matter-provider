require "json"
require "json-schema"

module App
  enum DeviceType
    OnOffLight
    DimmableLight
  end

  module DeviceTypes
    record DeviceTypeInfo, type : DeviceType, label : String do
      include JSON::Serializable

      def initialize(@type : DeviceType)
        @label = @type.to_s.underscore.gsub('_', ' ').titleize
      end
    end

    # Settings struct for On/Off Light devices
    struct OnOffSettings
      include JSON::Serializable

      @[JSON::Field(description: "Initial on/off state when device is created")]
      property? initial_state : Bool = false

      @[JSON::Field(description: "Display name for the device", min_length: 1, max_length: 64)]
      property name : String? = nil

      def initialize(@initial_state : Bool = false, @name : String? = nil)
      end
    end

    # Settings struct for Dimmable Light devices
    struct DimmableSettings
      include JSON::Serializable

      @[JSON::Field(description: "Initial on/off state when device is created")]
      property? initial_state : Bool = false

      @[JSON::Field(description: "Initial brightness level (0-100 percent)", minimum: 0, maximum: 100)]
      property initial_level : Int32 = 50

      @[JSON::Field(description: "Minimum brightness level (0-100 percent)", minimum: 0, maximum: 100)]
      property min_level : Int32 = 1

      @[JSON::Field(description: "Maximum brightness level (0-100 percent)", minimum: 0, maximum: 100)]
      property max_level : Int32 = 100

      @[JSON::Field(description: "Display name for the device", min_length: 1, max_length: 64)]
      property name : String? = nil

      def initialize(
        @initial_state : Bool = false,
        @initial_level : Int32 = 50,
        @min_level : Int32 = 1,
        @max_level : Int32 = 100,
        @name : String? = nil,
      )
      end
    end

    def self.list : Array(DeviceTypeInfo)
      DeviceType.values.map { |device_type| DeviceTypeInfo.new(device_type) }
    end

    def self.valid?(type : DeviceType) : Bool
      true
    end

    def self.valid?(type : String) : Bool
      !DeviceType.parse?(type).nil?
    end

    def self.schema(type : DeviceType) : JSON::Any
      case type
      in .on_off_light?   then JSON.parse(OnOffSettings.json_schema.to_json)
      in .dimmable_light? then JSON.parse(DimmableSettings.json_schema.to_json)
      end
    end

    def self.schema(type : String) : JSON::Any?
      DeviceType.parse?(type).try { |device_type| schema(device_type) }
    end

    def self.validate_settings(type : DeviceType, settings : JSON::Any) : Hash(String, String)?
      errors = {} of String => String

      case type
      in .on_off_light?   then validate_onoff_settings(settings, errors)
      in .dimmable_light? then validate_dimmable_settings(settings, errors)
      end

      errors.empty? ? nil : errors
    end

    def self.validate_settings(type : String, settings : JSON::Any) : Hash(String, String)?
      device_type = DeviceType.parse?(type)
      return {"type" => "unknown device type"} unless device_type

      validate_settings(device_type, settings)
    end

    private def self.validate_bool(key : String, value : JSON::Any, errors : Hash(String, String)) : Nil
      errors[key] = "must be a boolean" unless value.raw.is_a?(Bool)
    end

    private def self.validate_name(value : JSON::Any, errors : Hash(String, String)) : Nil
      if s = value.as_s?
        if s.empty?
          errors["name"] = "must not be empty"
        elsif s.size > 64
          errors["name"] = "must be at most 64 characters"
        end
      else
        errors["name"] = "must be a string"
      end
    end

    private def self.validate_percent(key : String, value : JSON::Any, errors : Hash(String, String)) : Nil
      if i = value.as_i?
        errors[key] = "must be between 0 and 100" if i < 0 || i > 100
      else
        errors[key] = "must be an integer"
      end
    end

    private def self.validate_onoff_settings(settings : JSON::Any, errors : Hash(String, String)) : Nil
      settings.as_h.each do |key, value|
        case key
        when "initial_state" then validate_bool(key, value, errors)
        when "name"          then validate_name(value, errors)
        else                      errors[key] = "unknown property"
        end
      end
    rescue
      errors["root"] = "must be an object"
    end

    private def self.validate_dimmable_settings(settings : JSON::Any, errors : Hash(String, String)) : Nil
      settings.as_h.each do |key, value|
        case key
        when "initial_state"                           then validate_bool(key, value, errors)
        when "initial_level", "min_level", "max_level" then validate_percent(key, value, errors)
        when "name"                                    then validate_name(value, errors)
        else                                                errors[key] = "unknown property"
        end
      end
    rescue
      errors["root"] = "must be an object"
    end
  end
end
