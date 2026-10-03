# frozen_string_literal: true

class Account < ActiveRecord::Base
  TIME_FORMATS = DeviceTimeFormatter::FORMATS

  encrypts :name

  has_many :account_users, dependent: :destroy
  has_many :users, through: :account_users
  has_many :locations, dependent: :restrict_with_error
  has_many :devices, through: :locations

  validates :name, presence: true
  validates :time_format, inclusion: {in: TIME_FORMATS}

  def support_access?
    support_access_at.present?
  end
end
