require "spec"
require "file_utils"

# Helper methods for testing controllers (curl, with_server, context)
require "action-controller/spec_helper"

# Your application config
require "../src/config"

# Test data directory
SPEC_DATA_PATH = File.join(Dir.tempdir, "matter_provider_spec_#{Process.pid}")

module SpecProviderHelper
  class_getter provider : App::Provider { create_provider }

  private def self.create_provider : App::Provider
    FileUtils.mkdir_p(SPEC_DATA_PATH) unless Dir.exists?(SPEC_DATA_PATH)
    App::Provider.new(SPEC_DATA_PATH)
  end
end

# Ensure provider is initialized before any tests
Spec.before_each do
  SpecProviderHelper.provider
end

# Cleanup after specs
Spec.after_suite do
  FileUtils.rm_rf(SPEC_DATA_PATH) if Dir.exists?(SPEC_DATA_PATH)
end
