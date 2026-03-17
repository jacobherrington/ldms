require_relative "../test_helper"
require "open3"

class LdmsCommandTest < Minitest::Test
  def test_help_includes_install_and_bootstrap_commands
    stdout, status = Open3.capture2("bash", "bin/ldms", "help", chdir: File.expand_path("../..", __dir__))

    assert status.success?
    assert_includes stdout, "install"
    assert_includes stdout, "bootstrap"
  end
end
