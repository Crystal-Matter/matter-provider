require "./spec_helper"

describe App::Root do
  client = AC::SpecHelper.client

  describe "GET /" do
    it "returns provider info" do
      result = client.get("/")
      result.status_code.should eq(200)

      body = JSON.parse(result.body)
      body["name"].as_s.should eq("matter-provider")
      body["version"].as_s.should_not be_empty
      body["uptime_seconds"].as_i64.should be >= 0
      body["device_types"].as_a.should_not be_empty
      body["counts"]["devices"].as_i.should be >= 0
      body["counts"]["healthy"].as_i.should be >= 0
      body["counts"]["unhealthy"].as_i.should be >= 0
    end
  end

  describe "GET /health" do
    it "returns health status" do
      result = client.get("/health")
      result.status_code.should eq(200)

      body = JSON.parse(result.body)
      body["status"].as_s.should eq("ok")
    end
  end

  describe "commissioning" do
    headers = HTTP::Headers{"Content-Type" => "application/json"}

    describe "GET /commission" do
      it "returns status with commission_info when not yet commissioned" do
        result = client.get("/commission")
        result.status_code.should eq(200)

        body = JSON.parse(result.body)
        body["active"].as_bool.should be_true
        body["commissioned"].as_bool.should be_false
        body["fabric_count"].as_i.should eq(0)

        # When active, includes commission_info
        info = body["commission_info"]
        info["qr_payload"].as_s.should start_with("MT:")
        info["manual_pairing_code"].as_s.should_not be_empty
        info["discriminator"].as_i.should be > 0
      end
    end

    describe "POST /commission" do
      it "returns commissioning info for the bridge" do
        result = client.post("/commission", headers: headers, body: "{}")
        result.status_code.should eq(200)

        body = JSON.parse(result.body)
        body["qr_payload"].as_s.should start_with("MT:")
        body["manual_pairing_code"].as_s.should_not be_empty
        body["discriminator"].as_i.should be > 0
      end
    end
  end
end
