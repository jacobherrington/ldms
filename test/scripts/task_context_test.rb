require_relative "../test_helper"
require "json"
require "open3"
require "tempfile"

class TaskContextScriptTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_bin_ldms_help_lists_task_command
    stdout, status = Open3.capture2("bash", "bin/ldms", "help", chdir: ROOT)

    assert status.success?
    assert_includes stdout, "task"
  end

  def test_task_context_json_output_includes_task_context
    stdout, status = Open3.capture2(
      "ruby",
      "scripts/task_context.rb",
      "--task",
      "implement memory loop",
      "--json",
      chdir: ROOT
    )

    assert status.success?
    payload = JSON.parse(stdout)
    assert_equal "implement memory loop", payload.fetch("task_context").fetch("task")
  end

  def test_task_context_processes_review_file_when_provided
    review_file = Tempfile.new("task-review")
    review_file.write("Convention: Keep task wrapper single-command\n")
    review_file.flush

    stdout, status = Open3.capture2(
      "ruby",
      "scripts/task_context.rb",
      "--task",
      "improve task flow",
      "--json",
      "--review-file",
      review_file.path,
      chdir: ROOT
    )

    assert status.success?
    payload = JSON.parse(stdout)
    result = payload.fetch("review_result")
    assert_equal "ok", result.fetch("status")
    assert result.fetch("saved_count") >= 1
  ensure
    review_file.close!
  end
end
