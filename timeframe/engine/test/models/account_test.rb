# frozen_string_literal: true

require "test_helper"

class AccountTest < ActiveSupport::TestCase
  def test_support_access
    account = Account.new
    support_access_at = nil
    account.define_singleton_method(:support_access_at) { support_access_at }

    refute account.support_access?

    support_access_at = Time.current
    assert account.support_access?
  end
end
