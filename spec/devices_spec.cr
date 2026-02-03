require "./spec_helper"

describe App::DevicesController do
  client = AC::SpecHelper.client
  headers = HTTP::Headers{"Content-Type" => "application/json"}

  describe "GET /devices" do
    it "returns array of devices" do
      result = client.get("/devices")
      result.status_code.should eq(200)

      body = JSON.parse(result.body)
      body.as_a.should be_a(Array(JSON::Any))
    end
  end

  describe "POST /devices" do
    it "creates an on_off_light device" do
      payload = {
        type:     "on_off_light",
        label:    "Test On/Off Light",
        settings: {initial_state: true},
      }.to_json

      result = client.post("/devices", headers: headers, body: payload)
      result.status_code.should eq(201)

      body = JSON.parse(result.body)
      body["id"].as_s.should start_with("dev-")
      body["type"].as_s.should eq("on_off_light")
      body["label"].as_s.should eq("Test On/Off Light")
      body["settings"]["initial_state"].as_bool.should be_true

      # Cleanup
      client.delete("/devices/#{body["id"].as_s}")
    end

    it "creates a dimmable_light device" do
      payload = %({"type":"dimmable_light","label":"Test Dimmable Light","settings":{"initial_state":false,"initial_level":75}})

      result = client.post("/devices", headers: headers, body: payload)
      result.status_code.should eq(201)

      body = JSON.parse(result.body)
      body["id"].as_s.should start_with("dev-")
      body["type"].as_s.should eq("dimmable_light")
      body["label"].as_s.should eq("Test Dimmable Light")
      body["settings"]["initial_level"].as_i.should eq(75)

      # Cleanup
      client.delete("/devices/#{body["id"].as_s}")
    end

    it "rejects invalid device type" do
      payload = {
        type:  "invalid_type",
        label: "Test Device",
      }.to_json

      result = client.post("/devices", headers: headers, body: payload)
      result.status_code.should eq(400)

      body = JSON.parse(result.body)
      body["error"].as_s.should eq("invalid_type")
    end

    it "validates settings - out of range level" do
      payload = %({"type":"dimmable_light","label":"Test Dimmable Light","settings":{"initial_level":150}})

      result = client.post("/devices", headers: headers, body: payload)
      result.status_code.should eq(422)

      body = JSON.parse(result.body)
      body["error"].as_s.should eq("validation_failed")
    end
  end

  describe "device CRUD operations" do
    it "full CRUD lifecycle for onoff device" do
      # CREATE
      payload = %({"type":"on_off_light","label":"CRUD Test Device","settings":{"initial_state":false}})
      create_result = client.post("/devices", headers: headers, body: payload)
      create_result.status_code.should eq(201)

      device = JSON.parse(create_result.body)
      device_id = device["id"].as_s
      device_id.should start_with("dev-")

      # READ - detail
      read_result = client.get("/devices/#{device_id}")
      read_result.status_code.should eq(200)

      detail = JSON.parse(read_result.body)
      detail["id"].as_s.should eq(device_id)
      detail["type"].as_s.should eq("on_off_light")
      detail["label"].as_s.should eq("CRUD Test Device")
      detail["health"]["status"].as_s.should eq("ok")
      detail["snapshot"]["on"].as_bool.should be_false
      detail["endpoint"].as_i.should be > 0

      # READ - state
      state_result = client.get("/devices/#{device_id}/state")
      state_result.status_code.should eq(200)

      state = JSON.parse(state_result.body)
      state["on"].as_bool.should be_false
      state["reachable"].as_bool.should be_true

      # UPDATE
      update_result = client.patch("/devices/#{device_id}", headers: headers, body: %({"label":"Updated Device"}))
      update_result.status_code.should eq(200)

      updated = JSON.parse(update_result.body)
      updated["label"].as_s.should eq("Updated Device")

      # DELETE
      delete_result = client.delete("/devices/#{device_id}")
      delete_result.status_code.should eq(200)

      deleted = JSON.parse(delete_result.body)
      deleted["deleted"].as_bool.should be_true

      # Verify deletion
      verify_result = client.get("/devices/#{device_id}")
      verify_result.status_code.should eq(404)
    end
  end

  describe "device control operations" do
    it "controls onoff device on/off/toggle" do
      # Create device
      create_result = client.post("/devices", headers: headers, body: %({"type":"on_off_light","label":"Control Test"}))
      device_id = JSON.parse(create_result.body)["id"].as_s

      # Initially off
      state = JSON.parse(client.get("/devices/#{device_id}/state").body)
      state["on"].as_bool.should be_false

      # Turn on
      on_result = client.post("/devices/#{device_id}/on", headers: headers, body: "{}")
      on_result.status_code.should eq(200)
      JSON.parse(on_result.body)["on"].as_bool.should be_true

      # Verify state
      state = JSON.parse(client.get("/devices/#{device_id}/state").body)
      state["on"].as_bool.should be_true

      # Turn off
      off_result = client.post("/devices/#{device_id}/off", headers: headers, body: "{}")
      off_result.status_code.should eq(200)
      JSON.parse(off_result.body)["on"].as_bool.should be_false

      # Toggle (should turn on)
      toggle_result = client.post("/devices/#{device_id}/toggle", headers: headers, body: "{}")
      toggle_result.status_code.should eq(200)
      JSON.parse(toggle_result.body)["on"].as_bool.should be_true

      # Toggle again (should turn off)
      toggle_result = client.post("/devices/#{device_id}/toggle", headers: headers, body: "{}")
      JSON.parse(toggle_result.body)["on"].as_bool.should be_false

      # Cleanup
      client.delete("/devices/#{device_id}")
    end

    it "refresh returns health and snapshot" do
      create_result = client.post("/devices", headers: headers, body: %({"type":"on_off_light","label":"Refresh Test"}))
      device_id = JSON.parse(create_result.body)["id"].as_s

      refresh_result = client.post("/devices/#{device_id}/refresh", headers: headers, body: "{}")
      refresh_result.status_code.should eq(200)

      body = JSON.parse(refresh_result.body)
      body["health"]["status"].as_s.should eq("ok")
      body["snapshot"]["on"]?.should_not be_nil

      client.delete("/devices/#{device_id}")
    end
  end

  describe "dimmable device level control" do
    it "controls level on dimmable device" do
      # Create dimmable device
      create_result = client.post("/devices", headers: headers, body: %({"type":"dimmable_light","label":"Level Test","settings":{"initial_level":50}}))
      create_result.status_code.should eq(201)
      device_id = JSON.parse(create_result.body)["id"].as_s

      # Check initial state
      state = JSON.parse(client.get("/devices/#{device_id}/state").body)
      state["level"].as_i.should eq(50)

      # Set level to 75
      level_result = client.post("/devices/#{device_id}/level", headers: headers, body: %({"level":75}))
      level_result.status_code.should eq(200)
      JSON.parse(level_result.body)["level"].as_i.should eq(75)

      # Verify level persisted
      state = JSON.parse(client.get("/devices/#{device_id}/state").body)
      state["level"].as_i.should eq(75)

      # Cleanup
      client.delete("/devices/#{device_id}")
    end

    it "rejects level control on non-dimmable device" do
      # Create onoff device
      create_result = client.post("/devices", headers: headers, body: %({"type":"on_off_light","label":"OnOff Only"}))
      device_id = JSON.parse(create_result.body)["id"].as_s

      # Try to set level
      level_result = client.post("/devices/#{device_id}/level", headers: headers, body: %({"level":50}))
      level_result.status_code.should eq(400)

      body = JSON.parse(level_result.body)
      body["error"].as_s.should eq("invalid_device_type")

      # Cleanup
      client.delete("/devices/#{device_id}")
    end
  end

  describe "error handling" do
    it "returns 404 for non-existent device" do
      result = client.get("/devices/nonexistent-id")
      result.status_code.should eq(404)

      body = JSON.parse(result.body)
      body["error"].as_s.should eq("not_found")
    end

    it "returns 404 for delete on non-existent device" do
      result = client.delete("/devices/nonexistent-id")
      result.status_code.should eq(404)
    end

    it "returns 404 for operations on non-existent device" do
      result = client.post("/devices/nonexistent-id/on", headers: headers, body: "{}")
      result.status_code.should eq(404)

      result = client.post("/devices/nonexistent-id/toggle", headers: headers, body: "{}")
      result.status_code.should eq(404)
    end
  end
end
