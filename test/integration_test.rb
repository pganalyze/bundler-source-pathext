# frozen_string_literal: true

# Integration tests for the plugin. These shell out to a real `bundle install`
# in a throwaway app that pulls in a fixture gem with a native extension through
# the plugin, since that is the only way to exercise how Bundler loads and uses
# a source plugin.
#
# Run with the default Bundler:
#
#   ruby test/integration_test.rb
#
# Or against a specific one (the version has to be installed):
#
#   BUNDLER_VERSION=4.0.18 ruby test/integration_test.rb

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'rubygems/package'
require 'tmpdir'

class IntegrationTest < Minitest::Test
  PLUGIN_ROOT = File.expand_path('..', __dir__)
  FIXTURE = File.expand_path('fixtures/mygem', __dir__)

  # Bundler passes these to child processes to keep them inside its own bundle,
  # which would make the `bundle install` calls below use the wrong Gemfile.
  UNSET_ENV = {
    'BUNDLE_BIN_PATH' => nil,
    'BUNDLE_GEMFILE' => nil,
    'BUNDLE_LOCKFILE' => nil,
    'BUNDLER_SETUP' => nil,
    'RUBYLIB' => nil,
    'RUBYOPT' => nil,
  }.freeze

  def setup
    @app = Dir.mktmpdir('bundler-source-pathext-')
    FileUtils.cp_r(FIXTURE, File.join(@app, 'mygem'))

    # The plugin has to be declared before the source that uses it, otherwise
    # Bundler infers it from the source type and installs it from RubyGems.
    File.write(File.join(@app, 'Gemfile'), <<~GEMFILE)
      source "https://rubygems.org"

      plugin "bundler-source-pathext", path: #{PLUGIN_ROOT.inspect}

      source "./mygem", type: "pathext" do
        gem "mygem"
      end
    GEMFILE
  end

  def teardown
    FileUtils.remove_entry(@app) if @app && File.directory?(@app)
  end

  def test_builds_the_extension_and_makes_it_loadable
    bundle 'install'

    assert_path_exists File.join(@app, 'mygem', 'lib', 'mygem', "mygem_native.#{RbConfig::CONFIG["DLEXT"]}")
    assert_path_exists File.join(@app, 'mygem', 'tmp', RUBY_PLATFORM, 'mygem', RUBY_VERSION, 'gem.build_complete')
    assert_equal 'built', built_marker
  end

  # This is the reason the plugin exists: local gems keep their version when
  # their source changes, so a previously built extension must not be reused.
  def test_rebuilds_the_extension_when_its_source_changed
    bundle 'install'
    assert_equal 'built', built_marker

    source = File.join(@app, 'mygem', 'ext', 'mygem', 'mygem.c')
    rebuilt = File.read(source).sub('rb_str_new_cstr("built")', 'rb_str_new_cstr("rebuilt")')
    refute_equal File.read(source), rebuilt, 'the fixture no longer contains the marker string'
    File.write(source, rebuilt)
    bundle 'install'

    assert_equal 'rebuilt', built_marker
  end

  # Bundler 2.6 and newer skip plugins whose load paths don't exist, so every
  # require path the gemspec declares needs to be part of the built gem.
  def test_packaged_gem_ships_every_require_path_it_declares
    gem_file = File.join(@app, 'bundler-source-pathext.gem')
    run!('gem', 'build', 'bundler-source-pathext.gemspec', '-o', gem_file, chdir: PLUGIN_ROOT)
    spec = Gem::Package.new(gem_file).spec

    spec.require_paths.each do |require_path|
      next if require_path == '.'

      assert spec.files.any? { |file| file.start_with?("#{require_path}/") },
             "the gem declares the require path #{require_path.inspect} but ships no files in it, " \
             'which makes Bundler skip the plugin'
    end
  end

  private

  def built_marker
    bundle('exec', 'ruby', '-e', 'require "mygem"; print MyGemNative::BUILT').strip
  end

  def bundle(*args)
    run!('bundle', *args, chdir: @app)
  end

  def run!(*command, chdir:)
    output, status = Open3.capture2e(UNSET_ENV, *command, chdir: chdir)
    assert status.success?, "`#{command.join(" ")}` failed with #{status.exitstatus}:\n#{output}"
    output
  end
end
