# frozen_string_literal: true

class AddProviderMetadataToCalendarEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :calendar_events, :provider_url, :string
    add_column :calendar_events, :provider_etag, :string
  end
end
