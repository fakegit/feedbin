class Feed < ApplicationRecord
  has_many :subscriptions
  has_many :podcast_subscriptions
  has_many :entries
  has_many :users, through: :subscriptions
  has_many :unread_entries
  has_many :starred_entries
  has_many :feed_stats

  has_many :taggings
  has_many :tags, through: :taggings

  has_one :favicon, foreign_key: "host", primary_key: "host"
  has_one :newsletter_sender

  before_create :set_host
  before_save :set_hubs
  after_create :refresh_favicon

  after_commit :web_sub_subscribe, on: :create

  attribute :crawl_data, CrawlDataType.new
  attr_accessor :count, :tags
  attr_readonly :feed_url

  after_initialize :default_values

  enum feed_type: {xml: 0, newsletter: 1, twitter: 2, twitter_home: 3, pages: 4}

  store :settings, accessors: [:custom_icon, :current_feed_url, :custom_icon_format], coder: JSON

  def twitter_user?
    twitter_user.present?
  end

  def twitter_user
    @twitter_user ||= Twitter::User.new(options["twitter_user"].deep_symbolize_keys)
  rescue
    nil
  end

  def twitter_feed?
    twitter? || twitter_home?
  end

  def tag_with_params(params, user)
    tags = []
    tags.concat params[:tag_id].values if params[:tag_id]
    tags.concat params[:tag_name] if params[:tag_name]
    tags = tags.join(",")
    tag(tags, user)
  end

  def tag(names, user, delete_existing = true)
    taggings = []
    if delete_existing
      Tagging.where(user_id: user, feed_id: id).destroy_all
    end
    names = names.split(",") if names.is_a?(String)
    names.map do |name|
      name = name.strip
      unless name.blank?
        tag = Tag.where(name: name.strip).first_or_create!
        taggings << self.taggings.where(user: user, tag: tag).first_or_create!
      end
    end
    taggings
  end

  def host_letter
    letter = "default"
    if host
      if segment = host.split(".")[-2]
        letter = segment[0].downcase
      end
    end
    letter
  end

  def icon
    options.dig("json_feed", "icon") || custom_icon
  end

  def self.create_from_parsed_feed(parsed_feed)
    record = parsed_feed.to_feed
    create_with(record).create_or_find_by!(feed_url: record[:feed_url]).tap do |new_feed|
      parsed_feed.entries.each do |parsed_entry|
        entry_hash = parsed_entry.to_entry
        threader = Threader.new(entry_hash, new_feed)
        unless threader.thread
          new_feed.entries.create_with(entry_hash).create_or_find_by(public_id: entry_hash[:public_id])
        end
      end
    end
  end

  def check
    Feedkit::Request.download(feed_url)
  end

  def self.include_user_title
    feeds = select("feeds.*, subscriptions.title AS user_title")
    feeds.map do |feed|
      if feed.user_title
        feed.override_title(feed.user_title)
      end
      feed.title ||= "Untitled"
      feed
    end
    feeds.natural_sort_by { |feed| feed.title }
  end

  def string_id
    id.to_s
  end

  def set_host
    self.host = URI.parse(site_url).host
  rescue Exception
    Rails.logger.info { "Failed to set host for feed: %s" % site_url }
  end

  def override_title(title)
    @original_title = self.title
    self.title = title
  end

  def original_title
    @original_title || title
  end

  def priority_refresh(user = nil)
    if twitter_feed?
      if 10.minutes.ago > updated_at
        FeedCrawler::TwitterSchedule.new.enqueue_feed(self, user)
      end
    else
      FeedCrawler::DownloaderCritical.perform_async(id, feed_url, subscriptions_count, crawl_data.to_h)
    end
  end

  def list_unsubscribe
    options.dig("email_headers", "List-Unsubscribe")
  end

  def self.search(url)
    where("feed_url ILIKE :query", query: "%#{url}%")
  end

  def json_feed
    options&.respond_to?(:dig) && options&.dig("json_feed")
  end

  def has_subscribers?
    subscriptions_count > 0
  end

  def web_sub_secret
    Digest::SHA256.hexdigest([id, Rails.application.secrets.secret_key_base].join("-"))
  end

  def web_sub_callback(debug: false)
    uri = URI(ENV["PUSH_URL"])
    signature = OpenSSL::HMAC.hexdigest("sha256", web_sub_secret, id.to_s)
    params = {}
    params[:debug] = true if debug
    Rails.application.routes.url_helpers.web_sub_verify_url(id, web_sub_callback_signature, protocol: uri.scheme, host: uri.host, params: params)
  end

  def web_sub_callback_signature
    OpenSSL::HMAC.hexdigest("sha256", web_sub_secret, id.to_s)
  end

  def web_sub_subscribe
    WebSub::Subscribe.perform_async(id)
  end

  def hubs
    if self[:hubs].blank? && !known_hubs.blank?
      known_hubs
    else
      self[:hubs]
    end
  end

  def self_url
    if youtube_channel_id
      "https://www.youtube.com/xml/feeds/videos.xml?channel_id=#{youtube_channel_id}"
    else
      self[:self_url]
    end
  end

  def known_hubs
    if youtube_channel_id
      ["https://pubsubhubbub.appspot.com"]
    end
  end

  def set_hubs
    if known_hubs.present?
      self[:hubs] = known_hubs
    end
  end

  def youtube_channel_id
    youtube_prefix = Regexp.new(/^https?:\/\/www\.youtube\.com\/feeds\/videos\.xml\?channel_id=([^#\?&]*)/)
    if feed_url =~ youtube_prefix && self[:self_url] =~ youtube_prefix
      $1
    else
      nil
    end
  end

  def redirect_key
    "refresher_redirect_stable_%d" % id
  end

  def rebase_url(original_url)
    base_url = Addressable::URI.heuristic_parse(site_url)
    original_url = Addressable::URI.heuristic_parse(original_url)
    Addressable::URI.join(base_url, original_url)
  end

  private

  def refresh_favicon
    FaviconFetcher.perform_async(host)
    ImageCrawler::ItunesFeedImage.perform_async(id)
  end

  def default_values
    if respond_to?(:options)
      self.options ||= {}
    end
  end
end
