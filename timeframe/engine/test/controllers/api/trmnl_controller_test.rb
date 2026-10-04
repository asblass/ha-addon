# frozen_string_literal: true

require "test_helper"

class Api::TrmnlControllerTest < ActionDispatch::IntegrationTest
  def setup
    PendingDevice.destroy_all
    DeviceMetricBucket.delete_all
    Device.where(model: %w[trmnl_og reterminal_e1003 trmnl_x]).destroy_all
  end

  # --- /api/setup ---

  test "setup creates a pending device" do
    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 200, json["status"]
    assert json["api_key"].present?
    assert json["friendly_id"].present?
    assert_nil json["image_url"]
    assert_match(/Enter this code/, json["message"])

    pending = PendingDevice.find_by(mac_address: "AA:BB:CC:DD:EE:FF")
    assert pending.present?
  end

  test "setup is idempotent for an existing paired device and display still finds it" do
    mac = "AA:BB:CC:DD:EE:FF"
    pending = PendingDevice.create!(
      mac_address: mac,
      api_key: SecureRandom.hex(16),
      friendly_id: SecureRandom.alphanumeric(6).upcase,
      model: "trmnl_x"
    )
    device = pending.claim!(location: test_location, name: "Paired TRMNL X", model: "trmnl_x")
    device.update!(
      last_connection_at: Time.current,
      cached_image: Base64.strict_encode64("fake png"),
      cached_image_at: Time.current
    )
    original_api_key = device.api_key
    original_friendly_id = device.friendly_id
    original_location_id = device.location_id
    original_last_connection_at = device.last_connection_at

    get "/api/setup", headers: {"ID" => mac, "Model" => "trmnl_x", "FW-Version" => "1.8.1"}

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 200, json["status"]
    assert_equal original_api_key, json["api_key"]
    assert_equal original_friendly_id, json["friendly_id"]
    assert_equal "Device already paired", json["message"]

    device.reload
    assert_equal mac, device.mac_address
    assert_equal original_api_key, device.api_key
    assert_equal original_friendly_id, device.friendly_id
    assert_equal original_location_id, device.location_id
    assert_equal original_last_connection_at, device.last_connection_at
    assert_equal device.id, pending.reload.claimed_device_id
    assert_equal 1, PendingDevice.where(mac_address: mac).count

    get "/api/display", headers: {"ID" => mac}

    assert_response :success
    assert_equal 0, JSON.parse(response.body)["status"]
    assert_equal device.id, Device.find_by(mac_address: mac).id
    assert_equal 1, PendingDevice.where(mac_address: mac).count
  end

  test "setup returns existing pending device for duplicate MAC" do
    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}
    first_id = JSON.parse(response.body)["friendly_id"]

    get "/api/setup", headers: {"ID" => "AA:BB:CC:DD:EE:FF"}
    second_id = JSON.parse(response.body)["friendly_id"]

    assert_equal first_id, second_id
    assert_equal 1, PendingDevice.where(mac_address: "AA:BB:CC:DD:EE:FF").count
  end

  test "setup preserves an existing device when firmware headers are present" do
    mac = "AA:BB:CC:DD:EE:FF"
    device = create_trmnl_device!(mac: mac, model: "trmnl_x")
    original_api_key = device.api_key

    get "/api/setup", headers: {"ID" => mac, "Model" => "trmnl_x", "FW-Version" => "1.8.1"}

    assert_response :success
    device.reload
    assert_not_equal "1.8.1", device.firmware_version
    assert_equal mac, device.mac_address
    assert_equal original_api_key, device.api_key
    assert_nil PendingDevice.find_by(mac_address: mac)
  end

  test "setup returns bad request without MAC address" do
    get "/api/setup"
    assert_response :bad_request
  end

  test "setup records the firmware model on a new pending device" do
    get "/api/setup", headers: {"ID" => "11:22:33:44:55:66", "Model" => "og"}
    assert_equal "trmnl_og", PendingDevice.find_by(mac_address: "11:22:33:44:55:66").model
  end

  test "setup backfills the model for a pending device created without one" do
    get "/api/setup", headers: {"ID" => "22:33:44:55:66:77"}
    pending = PendingDevice.find_by(mac_address: "22:33:44:55:66:77")
    assert_nil pending.model

    get "/api/setup", headers: {"ID" => "22:33:44:55:66:77", "Model" => "x"}
    assert_equal "trmnl_x", pending.reload.model
  end

  # --- /api/display ---

  test "display succeeds without access token" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {"ID" => device.mac_address}
      assert_response :success
    end
  end

  test "display succeeds with empty access token" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => ""}
      assert_response :success
    end
  end

  test "display returns 401 with wrong access token" do
    device = create_trmnl_device!

    get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => "wrong"}
    assert_response :unauthorized
  end

  test "display returns 401 without MAC address" do
    get "/api/display", headers: {"ACCESS_TOKEN" => "something"}
    assert_response :unauthorized
  end

  test "display adopts an unknown MAC into a pending registration and returns 202" do
    assert_nil PendingDevice.find_by(mac_address: "FF:EE:DD:CC:BB:AA")

    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :success
    assert_equal 202, JSON.parse(response.body)["status"]

    # The orphaned hardware is re-enrolled into pairing instead of dead-ending
    # on a 401, so the owner can pair it without a factory reset.
    pending = PendingDevice.find_by(mac_address: "FF:EE:DD:CC:BB:AA")
    assert pending.present?
    assert pending.pairing_code.present?
    assert pending.api_key.present?
  end

  test "display does not duplicate the pending for a repeatedly-polling unknown MAC" do
    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}

    assert_equal 1, PendingDevice.where(mac_address: "FF:EE:DD:CC:BB:AA").count
  end

  test "display returns 202 status in body for pending device MAC" do
    get "/api/setup", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :success

    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 202, json["status"]
  end

  test "display keeps a waiting pending device from expiring so its code stays pairable" do
    get "/api/setup", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    pending = PendingDevice.find_by(mac_address: "FF:EE:DD:CC:BB:AA")
    code = pending.pairing_code
    # Simulate the pairing code approaching the 60-minute expiry window.
    pending.update_column(:created_at, 59.minutes.ago)

    get "/api/display", headers: {"ID" => "FF:EE:DD:CC:BB:AA"}
    assert_response :success
    assert_equal 202, JSON.parse(response.body)["status"]

    pending.reload
    refute pending.expired?
    assert_equal code, pending.pairing_code
    assert PendingDevice.find_active_by_code(code)
  end

  test "display returns image data for valid device" do
    device = create_trmnl_device!

    # Pin to a daytime hour so the overnight (23:00-05:00 local) reduced refresh
    # rate never makes this assertion flaky.
    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      travel_to ActiveSupport::TimeZone["America/Chicago"].local(2026, 7, 17, 12, 0, 0) do
        get "/api/display", headers: {
          "ID" => device.mac_address,
          "ACCESS_TOKEN" => device.api_key,
          "Battery-Voltage" => "4.1",
          "FW-Version" => "1.8.1",
          "FW-Commit" => "f35414e",
          "RSSI" => "-69"
        }

        assert_response :success
        json = JSON.parse(response.body)
        assert_equal 0, json["status"]
        assert_match(/\Adisplay-.*\.png\z/, json["filename"])
        assert json["image_url"].include?("/signed_screenshot/")
        assert_equal 0, json["image_url_timeout"]
        assert_equal 900, json["refresh_rate"]
        assert_equal "sleep", json["special_function"]
        assert_equal false, json["reset_firmware"]
        assert_equal false, json["update_firmware"]
        assert_nil json["firmware_url"]
        assert_equal "default", json["temperature_profile"]

        device.reload
        assert device.last_connection_at.present?
        assert_equal 92, device.battery_level
        assert_equal "1.8.1", device.firmware_version
        assert_equal "f35414e", device.firmware_commit
        assert_equal(-69, device.rssi)
      end
    end
  end

  test "display skips refresh when cached image exists" do
    device = create_trmnl_device!
    cached_at = 5.minutes.ago
    device.update!(cached_image: "existingbase64", cached_image_at: cached_at, last_connection_at: 1.minute.ago)

    get "/api/display", headers: {
      "ID" => device.mac_address,
      "ACCESS_TOKEN" => device.api_key,
      "Battery-Voltage" => "3.9",
      "Percent-Charged" => "70",
      "USB-Connected" => "false"
    }

    assert_response :success
    bucket = device.device_metric_buckets.first!
    assert_equal 70, bucket.battery_percent_last
    assert_equal 3.9, bucket.battery_voltage_last
    assert_equal 1, bucket.poll_no_update_count
  end

  test "display succeeds when poll metrics cannot be recorded" do
    device = create_trmnl_device!
    device.update!(cached_image: "existingbase64", cached_image_at: Time.current)

    DeviceMetricBucket.stub :record_poll!, ->(**) { raise ActiveRecord::ConnectionNotEstablished, "metrics unavailable" } do
      get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => device.api_key}
    end

    assert_response :success
  end

  test "display prefers Percent-Charged and records charging state" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Battery-Voltage" => "3.6",
        "Percent-Charged" => "63",
        "Battery-Charging" => "1"
      }
    end

    device.reload
    assert_equal 63, device.battery_level
    assert device.charging?
    refute device.low_battery_warning?
  end

  test "display calibrates E1003 battery voltage to its usable range" do
    device = create_trmnl_device!(model: "reterminal_e1003")

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Battery-Voltage" => "4.08"
      }
    end

    assert_equal 100, device.reload.battery_level

    get "/api/display", headers: {
      "ID" => device.mac_address,
      "ACCESS_TOKEN" => device.api_key,
      "Battery-Voltage" => "3.144"
    }

    device.reload
    assert_equal 0, device.battery_level
    assert device.low_battery_warning?
  end

  test "display sets low battery warning when discharging below threshold" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Percent-Charged" => "20",
        "USB-Connected" => "false"
      }
    end

    device.reload
    assert_equal 20, device.battery_level
    refute device.charging?
    assert device.low_battery_warning?
  end

  test "display clears low battery warning once charging" do
    device = create_trmnl_device!
    device.update!(low_battery_warning: true)

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Percent-Charged" => "20",
        "Battery-Charging" => "true"
      }
    end

    device.reload
    assert device.charging?
    refute device.low_battery_warning?
  end

  test "display remains charging while USB is connected after active charging completes" do
    device = create_trmnl_device!

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Percent-Charged" => "100",
        "Battery-Charging" => "0",
        "USB-Connected" => "true"
      }
    end

    device.reload
    assert_equal 100, device.battery_level
    assert device.charging?
  end

  test "display clears the offline notification flag on reconnect" do
    device = create_trmnl_device!
    device.update!(device_offline_notified_at: 2.days.ago)

    ScreenshotService.stub :capture, "fakeimagedatabase64" do
      get "/api/display", headers: {"ID" => device.mac_address, "ACCESS_TOKEN" => device.api_key}
    end

    device.reload
    assert device.last_connection_at.present?
    assert_nil device.device_offline_notified_at
  end

  # --- /api/log ---

  test "log returns 204 with valid credentials" do
    device = create_trmnl_device!

    post "/api/log",
      params: {logs: [{message: "test"}]}.to_json,
      headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => device.api_key,
        "Content-Type" => "application/json"
      }

    assert_response :no_content
  end

  test "log returns 204 with empty access token" do
    device = create_trmnl_device!

    post "/api/log",
      params: {logs: [{message: "test"}]}.to_json,
      headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => "",
        "Content-Type" => "application/json"
      }

    assert_response :no_content
  end

  test "log returns 401 with invalid credentials" do
    device = create_trmnl_device!

    post "/api/log",
      params: {logs: [{message: "test"}]}.to_json,
      headers: {
        "ID" => device.mac_address,
        "ACCESS_TOKEN" => "wrong",
        "Content-Type" => "application/json"
      }

    assert_response :unauthorized
  end

  test "display returns confirmation data for unconfirmed device" do
    device = Device.create!(location: test_location,
      name: "Pending TRMNL",
      model: "trmnl_og",
      mac_address: "AA:BB:CC:11:22:33",
      confirmation_code: "ABC123")

    get "/api/display", headers: {"ID" => device.mac_address}

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["status"]
    assert_match(/confirmation/, json["filename"])
    assert_equal 30, json["refresh_rate"]
    assert_equal false, json["reset_firmware"]
    assert_equal false, json["update_firmware"]
    assert_nil json["firmware_url"]
    assert_equal "default", json["temperature_profile"]
  end

  private

  def create_trmnl_device!(mac: "11:22:33:44:55:66", model: "trmnl_og")
    Device.create!(location: test_location,
      name: "Test TRMNL #{mac}",
      model: model,
      mac_address: mac,
      confirmed_at: Time.current,
      confirmation_code: nil)
  end
end
