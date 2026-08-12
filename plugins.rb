# frozen_string_literal: true

require 'bundler-source-pathext'

# Note that Bundler loads this file once when the plugin is installed, and again
# when the plugin is used, and only keeps the sources registered by the latter.
# The registration therefore has to happen here, and not in the required file,
# which only gets loaded once per process.
BundlerSourcePathext.source 'pathext', BundlerSourcePathext::PathExtSource
