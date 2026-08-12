# frozen_string_literal: true

require 'fileutils'

class BundlerSourcePathext < Bundler::Plugin::API
  HAS_TARGET_RBCONFIG = Gem.rubygems_version >= Gem::Version.new("3.6")
  HAS_NJOBS = Gem.rubygems_version >= Gem::Version.new("4.0.2")

  class PathExtSource < Bundler::Source
    # Note that `opts` are the install options passed in by Bundler (:build_args,
    # :previous_spec, ...), whereas `options` are the source options that came
    # from the Gemfile or the lockfile.
    def install(spec, opts = {})
      using_message = "Using #{version_message(spec, opts[:previous_spec])} from #{self}"
      using_message += " and installing its executables" unless spec.executables.empty?
      print_using_message using_message
      generate_bin(spec, disable_extensions: true) # Turned off!

      build_local_extensions(spec, opts[:build_args])

      nil # no post-install message
    end

    # Bundler plugin api, we need to return a Bundler::Index
    def specs
      # A relative path in the Gemfile is relative to the Gemfile itself (i.e.
      # the bundler root), and not to the directory bundler was run from
      files = Dir.glob(File.join(File.expand_path(uri, root), '*.gemspec'))

      Bundler::Index.build do |index|
        files.each do |file|
          next unless spec = Bundler.load_gemspec(file)
          spec.installed_by_version = Gem::VERSION
          spec.source = self
          spec.extension_dir = File.join(File.dirname(file), 'tmp', RUBY_PLATFORM, spec.name, RUBY_VERSION)
          Bundler.rubygems.validate(spec)

          index << spec
        end
      end
    end

    # Set internal representation to fetch the gems/specs locally.
    #
    # When this is called, the source should try to fetch the specs and
    # install from the local system.
    def local!
      # not applicable
    end

    # Set internal representation to fetch the gems/specs from remote.
    #
    # When this is called, the source should try to fetch the specs and
    # install from remote path.
    def remote!
      # not applicable
    end

    # Set internal representation to fetch the gems/specs from app cache.
    #
    # When this is called, the source should try to fetch the specs and
    # install from the path provided by `app_cache_path`.
    def cached!
      # not applicable
    end

    # This is called to update the spec and installation.
    #
    # If the source plugin is loaded from lockfile or otherwise, it shall
    # refresh the cache/specs (e.g. git sources can make a fresh clone).
    def unlock!
      # not applicable
    end

    private

    def build_local_extensions(spec, build_args = nil)
      # Bundler passes in whatever "bundle config build.GEM" is set to, and the
      # source options allow setting build args for all gems of a source
      build_args = Array(build_args)
      build_args = Array(options['build_args']) if build_args.empty?
      build_args = Array(Bundler.rubygems.build_args) if build_args.empty?

      builder = Gem::Ext::Builder.new spec, build_args

      build_extensions(spec, build_args, builder)
    end

    def build_extensions(spec, build_args, builder)
      return if spec.extensions.empty?

      if build_args.empty?
        puts "Building native extensions for #{spec.name}. This could take a while..."
      else
        puts "Building native extensions for #{spec.name} with: '#{build_args.join " "}'"
        puts "This could take a while..."
      end

      dest_path = spec.extension_dir
      start = Time.now

      spec.extensions.each do |extension|
        builder_for_ext = if extension[/extconf/]
                            ExtConfAlwaysCopyBuilder
                          else
                            builder.builder_for(extension)
                          end

        # This throws a Gem::Ext::BuildError if building the extension fails
        build_extension spec, builder, builder_for_ext, extension, dest_path, build_args
      end
      puts format('  Finished %s after %0.2f seconds', spec.name, Time.now - start)
      FileUtils.touch(spec.gem_build_complete_path)
    end

    def build_extension(spec, builder, builder_for_ext, extension, dest_path, build_args) # :nodoc:
      results = []

      extension_dir =
        File.expand_path File.join(spec.full_gem_path, File.dirname(extension))
      lib_dir = File.join spec.full_gem_path, spec.raw_require_paths.first

      begin
        FileUtils.mkdir_p dest_path

        results = builder_for_ext.build(extension, dest_path,
                                        results, build_args, lib_dir, extension_dir)

        builder.verbose { results.join("\n") }

        builder.write_gem_make_out results.join "\n"
      rescue StandardError => e
        results << e.message
        builder.build_error(results.join("\n"), $@)
      end
    end

    def generate_bin(spec, options = {})
      gem_dir = Pathname.new(spec.full_gem_path)

      # Some gem authors put absolute paths in their gemspec
      # and we have to save them from themselves
      spec.files = spec.files.filter_map do |path|
        next path unless /\A#{Pathname::SEPARATOR_PAT}/o.match?(path)
        next if File.directory?(path)
        begin
          Pathname.new(path).relative_path_from(gem_dir).to_s
        rescue ArgumentError
          path
        end
      end

      installer = Path::Installer.new(
        spec,
        env_shebang: false,
        disable_extensions: options[:disable_extensions],
        build_args: options[:build_args],
        bundler_extension_cache_path: extension_cache_path(spec)
      )
      installer.post_install
    rescue Gem::InvalidSpecificationException => e
      Bundler.ui.warn "\n#{spec.name} at #{spec.full_gem_path} did not have a valid gemspec.\n" \
                      "This prevents bundler from installing bins or native extensions, but " \
                      "that may not affect its functionality."

      if !spec.extensions.empty? && !spec.email.empty?
        Bundler.ui.warn "If you need to use this package without installing it from a gem " \
                        "repository, please contact #{spec.email} and ask them " \
                        "to modify their .gemspec so it can work with `gem build`."
      end

      Bundler.ui.warn "The validation message from RubyGems was:\n  #{e.message}"
    end
  end

  # Modified version of Gem::Ext::ExtConfBuilder that always copies the built binary
  # to the destination path. This is necessary because when using local gems we cannot
  # rely on versions being bumped when the gem changes.
  require 'rubygems/ext'
  class ExtConfAlwaysCopyBuilder < Gem::Ext::Builder
    def self.build(extension, dest_path, results, args = [], lib_dir = nil, extension_dir = Dir.pwd,
      target_rbconfig = nil, n_jobs: nil)
      require "fileutils"
      require "tempfile"

      target_rbconfig ||= Gem.target_rbconfig if HAS_TARGET_RBCONFIG

      tmp_dest = Dir.mktmpdir(".gem.", extension_dir)

      # Some versions of `mktmpdir` return absolute paths, which will break make
      # if the paths contain spaces.
      #
      # As such, we convert to a relative path.
      tmp_dest_relative = get_relative_path(tmp_dest.clone, extension_dir)

      destdir = ENV["DESTDIR"]

      begin
        cmd = ruby << File.basename(extension)
        cmd << "--target-rbconfig=#{target_rbconfig.path}" if HAS_TARGET_RBCONFIG && target_rbconfig.path
        cmd.push(*args)

        run(cmd, results, 'ExtConfAlwaysCopy', extension_dir) do |s, r|
          mkmf_log = File.join(extension_dir, "mkmf.log")
          if File.exist? mkmf_log
            unless s.success?
              r << "To see why this extension failed to compile, please check" \
                " the mkmf.log which can be found here:\n"
              r << "  " + File.join(dest_path, "mkmf.log") + "\n"
            end
            FileUtils.mv mkmf_log, dest_path
          end
        end

        ENV["DESTDIR"] = nil

        if HAS_TARGET_RBCONFIG && HAS_NJOBS
          make dest_path, results, extension_dir, tmp_dest_relative, target_rbconfig: target_rbconfig, n_jobs: n_jobs
        elsif HAS_TARGET_RBCONFIG
          make dest_path, results, extension_dir, tmp_dest_relative, target_rbconfig: target_rbconfig
        else
          make dest_path, results, extension_dir, tmp_dest_relative
        end

        full_tmp_dest = File.join(extension_dir, tmp_dest_relative)

        is_cross_compiling = HAS_TARGET_RBCONFIG && target_rbconfig["platform"] != RbConfig::CONFIG["platform"]

        entries = (Dir.entries(full_tmp_dest) - %w[. ..]).map {|entry| File.join full_tmp_dest, entry }

        # MODIFIED
        # Rubygems copies the built files into the gem's lib directory, and then
        # additionally moves them into the extension install directory, but only
        # the ones that don't exist there yet. We install into a single location,
        # always overwriting, so a rebuilt extension leaves no stale binary behind.
        #
        # Note that install_extension_in_lib can be turned off through gemrc, and
        # that Rubygems intends to eventually default it to false, which would
        # make the extension directory the regular case rather than a fallback.
        #
        # Rubygems skips the copy into lib when cross-compiling, because that
        # directory is shared with the build for the host platform, and relies on
        # the extension install directory being specific to the target (it follows
        # Gem::Platform.local, which is derived from the target rbconfig). The
        # directory we use is keyed to the platform of the running Ruby, so we
        # have nowhere to put a cross-compiled build, and skip it entirely.
        unless is_cross_compiling
          if Gem.install_extension_in_lib && lib_dir
            FileUtils.mkdir_p lib_dir
            FileUtils.cp_r entries, lib_dir, remove_destination: true
          else
            FileUtils.cp_r entries, dest_path, remove_destination: true
          end
        end

        if HAS_TARGET_RBCONFIG
          make dest_path, results, extension_dir, tmp_dest_relative, ["clean"], target_rbconfig: target_rbconfig
        else
          make dest_path, results, extension_dir, tmp_dest_relative, ["clean"]
        end
      ensure
        ENV["DESTDIR"] = destdir
      end

      results
    rescue => error
      if defined?(Gem::Ext::Builder::NoMakefileError) && error.is_a?(Gem::Ext::Builder::NoMakefileError)
        results << error.message
        results << "Skipping make for #{extension} as no Makefile was found."
        # We are good, do not re-raise the error.
      else
        raise
      end
    ensure
      FileUtils.rm_rf tmp_dest if tmp_dest
    end

    def self.get_relative_path(path, base)
      path[0..base.length - 1] = "." if path.start_with?(base)
      path
    end
  end
end
