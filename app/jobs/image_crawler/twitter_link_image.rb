module ImageCrawler
  class TwitterLinkImage
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(public_id, image = nil, page_url = nil)
      public_id = public_id.split("-").first
      @entry = Entry.find_by_public_id(public_id)
      @image = image
      @page_url = page_url

      if @image
        receive
      else
        schedule
      end
    rescue ActiveRecord::RecordNotFound
    end

    def schedule
      FindImage.perform_async("#{@entry.public_id}-twitter", "twitter", [], @page_url)
    end

    def receive
      @entry.data["twitter_link_image_processed"] = @image["processed_url"]
      @entry.save!
    end
  end
end