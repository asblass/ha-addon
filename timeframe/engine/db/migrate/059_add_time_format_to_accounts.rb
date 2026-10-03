class AddTimeFormatToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :time_format, :string, default: "12h", null: false
  end
end