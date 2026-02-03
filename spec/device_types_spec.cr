require "./spec_helper"

describe App::DeviceTypesController do
  client = AC::SpecHelper.client

  describe "GET /device-types" do
    it "lists available device types" do
      result = client.get("/device-types")
      result.status_code.should eq(200)

      body = JSON.parse(result.body)
      device_types = body["device_types"].as_a

      device_types.size.should eq(2)

      types = device_types.map(&.["type"].as_s)
      types.should contain("on_off_light")
      types.should contain("dimmable_light")

      labels = device_types.map(&.["label"].as_s)
      labels.should contain("On Off Light")
      labels.should contain("Dimmable Light")
    end
  end

  describe "GET /device-types/:type/schema" do
    it "returns schema for on_off_light" do
      result = client.get("/device-types/on_off_light/schema")
      result.status_code.should eq(200)

      schema = JSON.parse(result.body)
      schema["type"].as_s.should eq("object")
      schema["properties"]["initial_state"]["type"].as_s.should eq("boolean")
      schema["properties"]["initial_state"]["description"].as_s.should_not be_empty
      # name is optional so uses anyOf
      schema["properties"]["name"]["anyOf"].as_a.size.should eq(2)
      schema["required"].as_a.map(&.as_s).should contain("initial_state")
    end

    it "returns schema for dimmable_light" do
      result = client.get("/device-types/dimmable_light/schema")
      result.status_code.should eq(200)

      schema = JSON.parse(result.body)
      schema["type"].as_s.should eq("object")
      schema["properties"]["initial_state"]["type"].as_s.should eq("boolean")
      schema["properties"]["initial_level"]["type"].as_s.should eq("integer")
      schema["properties"]["initial_level"]["minimum"].as_i.should eq(0)
      schema["properties"]["initial_level"]["maximum"].as_i.should eq(100)
      schema["properties"]["min_level"]["type"].as_s.should eq("integer")
      schema["properties"]["max_level"]["type"].as_s.should eq("integer")
      schema["required"].as_a.map(&.as_s).should contain("initial_level")
    end

    it "returns 404 for unknown type" do
      result = client.get("/device-types/unknown_type/schema")
      result.status_code.should eq(404)

      body = JSON.parse(result.body)
      body["error"].as_s.should eq("not_found")
    end
  end
end
