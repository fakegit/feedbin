module ImageCrawler
  class UploadImage
    include Sidekiq::Worker
    include ImageCrawlerHelper
    include SidekiqHelper

    sidekiq_options queue: local_queue("image_parallel"), retry: false

    def perform(public_id, preset_name, image_path, original_url, image_url)
      @public_id = public_id
      @preset_name = preset_name
      @original_url = original_url
      @image_path = image_path

      storage_url = upload
      send_to_feedbin(original_url: image_url, storage_url: storage_url)
      begin
        File.unlink(image_path)
      rescue Errno::ENOENT
      end

      DownloadCache.new(@original_url, public_id: @public_id, preset_name: @preset_name).save(storage_url: storage_url, image_url: image_url)
      Sidekiq.logger.info "UploadImage: public_id=#{@public_id} original_url=#{@original_url} storage_url=#{storage_url}"
    end

    def upload
      File.open(@image_path) do |file|
        response = Fog::Storage.new(STORAGE_OPTIONS).put_object(IMAGE_STORAGE, image_name, file, storage_options)
        URI::HTTPS.build(
          host: response.data[:host],
          path: response.data[:path]
        ).to_s
      end
    end
  end
end