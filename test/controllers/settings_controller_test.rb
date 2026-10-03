# frozen_string_literal: true

require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  def setup
    @account = test_user.accounts.first
    login_as(test_user, scope: :user)
  end

  def teardown
    Warden.test_reset!
  end

  test "show renders the settings form" do
    get settings_path
    assert_response :success
    assert_includes response.body, "account[temperature_unit]"
    assert_includes response.body, "account[speed_unit]"
    assert_includes response.body, "account[precipitation_unit]"
    assert_includes response.body, "account[time_format]"
    assert_includes response.body, "12-hour (9:30 PM)"
    assert_includes response.body, "24-hour (21:30)"
  end

  test "update saves valid units to the account" do
    patch settings_path, params: {account: {temperature_unit: "C", speed_unit: "kph", precipitation_unit: "mm", time_format: "24h"}}
    assert_redirected_to settings_path
    @account.reload
    assert_equal "C", @account.temperature_unit
    assert_equal "kph", @account.speed_unit
    assert_equal "mm", @account.precipitation_unit
    assert_equal "24h", @account.time_format
  end

  test "update ignores invalid unit values" do
    @account.update!(speed_unit: "mph")
    patch settings_path, params: {account: {temperature_unit: "C", speed_unit: "bogus"}}
    assert_redirected_to settings_path
    @account.reload
    assert_equal "C", @account.temperature_unit
    assert_equal "mph", @account.speed_unit
  end

  test "update ignores invalid time format values" do
    patch settings_path, params: {account: {time_format: "24-hour"}}

    assert_redirected_to settings_path
    assert_equal "12h", @account.reload.time_format
  end
end
