require "test_helper"
class Api::Podcasts::V1::QueuedEntriesControllerTest < ApiControllerTestCase
  setup do
    @user = users(:ben)
    @feed = @user.podcast_subscriptions.first.feed
    @entry = create_entry(@feed)
    @queued_entry = @user.queued_entries.first
  end

  test "should get index" do
    login_as @user
    get :index, format: :json
    assert_response :success
    data = parse_json
    assert_equal(@entry.id, data.first.dig("entry_id"))
    assert_equal(@entry.feed.id, data.first.dig("feed_id"))
    assert_not_nil data.first.dig("id")
    assert_not_nil data.first.dig("order")
    assert_not_nil data.first.dig("progress")
    assert_not_nil data.first.dig("created_at")
    assert_not_nil data.first.dig("updated_at")
  end

  test "should create" do
    api_content_type
    login_as @user
    @user.queued_entries.delete_all
    assert_difference "QueuedEntry.count", +1 do
      post :create, params: {entry_id: @entry.id, progress: 10, order: 10}, format: :json
      assert_response :success
    end
  end

  test "should delete" do
    api_content_type
    login_as @user

    assert_difference "QueuedEntry.count", -1 do
      post :destroy, params: {id: @queued_entry.entry_id}, format: :json
      assert_response :success
    end
  end

  test "should update" do
    api_content_type
    login_as @user

    progress = 10

    patch :update, params: {id: @queued_entry.entry_id, progress: progress, progress_updated_at: Time.now.iso8601(6)}, format: :json
    assert_response :success

    assert @queued_entry.reload.progress, progress
    assert_equal("progress", @queued_entry.attribute_changes.first.name)
  end

  test "should not update" do

    api_content_type
    login_as @user

    progress = 10

    patch :update, params: {id: @queued_entry.entry_id, progress: progress, progress_updated_at: 1.second.ago.iso8601(6)}, format: :json
    assert_response :success

    assert_equal 0, @queued_entry.reload.progress
  end

end
