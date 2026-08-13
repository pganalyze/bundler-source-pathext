Gem::Specification.new do |spec|
  spec.name          = "bundler-source-pathext"
  spec.version       = "0.4.0"
  spec.authors       = ["pganalyze Team"]
  spec.email         = ["team@pganalyze.com"]

  spec.summary = 'Bundler source plugin for local gems with native extensions'
  spec.description = 'Bundler source plugin that works like a path source, but also builds the ' \
                     'native extensions of the gems it provides, like a remote gem source does.'
  spec.homepage = 'https://github.com/pganalyze/bundler-path-build-ext'
  spec.license = 'BSD-3-Clause'
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
