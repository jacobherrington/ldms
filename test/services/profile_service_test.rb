require_relative "../test_helper"
require_relative "../../app/services/profile_service"
require "tmpdir"
require "fileutils"

class ProfileServiceTest < Minitest::Test
  def setup
    @service = DevMemory::Services::ProfileService.new
  end

  def test_load_profile_contains_developer_root
    profile = @service.load_profile
    assert profile.key?("developer")
  end

  def test_summary_is_non_empty
    summary = @service.summary
    refute_empty summary
    assert_includes summary, "Languages:"
  end

  def test_retrieval_profiles_are_available
    profiles = @service.retrieval_profiles
    assert profiles.key?("balanced")
    assert_equal "balanced", @service.default_retrieval_profile
  end

  def test_editable_profile_returns_expected_shape
    profile = @service.editable_profile
    assert profile.key?("languages")
    assert profile.key?("frameworks")
    assert profile.key?("style")
    assert profile.fetch("style").key?("comments")
  end

  def test_update_basic_profile_updates_allowed_fields
    with_temp_profile_service do |service, profile_path|
      updated = service.update_basic_profile!(
        {
          "languages" => ["Ruby", "JavaScript"],
          "frameworks" => ["Rails"],
          "style" => {
            "prefer_small_functions" => true,
            "prefer_explicit_types" => false,
            "comments" => "concise"
          }
        }
      )

      assert_equal ["Ruby", "JavaScript"], updated["languages"]
      assert_equal ["Rails"], updated["frameworks"]
      assert_equal "concise", updated.fetch("style").fetch("comments")

      reloaded = JSON.parse(File.read(profile_path))
      assert_equal ["Ruby", "JavaScript"], reloaded.fetch("developer").fetch("languages")
      assert_equal true, reloaded.fetch("developer").fetch("style").fetch("prefer_small_functions")
    end
  end

  def test_update_basic_profile_rejects_invalid_comments_mode
    with_temp_profile_service do |service, _profile_path|
      error = assert_raises(ArgumentError) do
        service.update_basic_profile!(
          {
            "languages" => ["Ruby"],
            "frameworks" => ["Rails"],
            "style" => {
              "prefer_small_functions" => true,
              "prefer_explicit_types" => true,
              "comments" => "verbose"
            }
          }
        )
      end

      assert_includes error.message, "style.comments"
    end
  end

  private

  def with_temp_profile_service
    Dir.mktmpdir("profile-service-test") do |dir|
      path = File.join(dir, "developer_profile.json")
      original_path = DevMemory::Services::ProfileService::PROFILE_PATH
      FileUtils.cp(original_path, path)
      service = DevMemory::Services::ProfileService.new(profile_path: path)
      yield service, path
    end
  end
end
