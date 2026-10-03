# frozen_string_literal: true

class AddScopesToGoogleAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :google_accounts, :scopes, :text
  end
end
