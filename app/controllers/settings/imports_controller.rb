class Settings::ImportsController < ApplicationController

  def index
    @user = current_user
    @tags = @user.feed_tags
    @download_options = @tags.map { |tag|
      [tag.name, tag.id]
    }
    @download_options.unshift(["All", "all"])

    render layout: "settings"
  end

  def create
    if rate_limited?(3, 1.day)
      redirect_to settings_import_export_url, alert: "Too many upload requests."
      return
    end

    upload = params.dig(:import, :upload)
    if !upload.respond_to?(:tempfile)
      redirect_to settings_import_export_url, alert: "No file uploaded."
      return
    elsif upload.tempfile.size > 500.kilobytes
      redirect_to settings_import_export_url, alert: "Import must be less than 500kb."
      return
    end

    @import = @user.imports.new(filename: upload.original_filename, xml: upload.tempfile.read)

    if @import.save
      redirect_to settings_import_export_url, notice: "Import has started."
    else
      @messages = @import.errors.full_messages
      flash[:error] = render_to_string partial: "shared/messages"
      redirect_to settings_import_export_url
    end
  end
end
