# frozen_string_literal: true

class AddHaSyncSupport < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :ha_sync_api_key, :text
    add_index :locations, :ha_sync_api_key, unique: true

    create_table :ha_syncs do |t|
      t.references :location, null: false, foreign_key: true, index: {unique: true}
      t.jsonb :entities, null: false, default: {}
      t.datetime :synced_at, null: false
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        Location.find_each do |location|
          location.update_column(:ha_sync_api_key, SecureRandom.hex(32))
        end
      end
    end
  end
end
