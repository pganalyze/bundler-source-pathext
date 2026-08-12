Gem::Specification.new do |spec|
  spec.name        = 'mygem'
  spec.version     = '0.1.0'
  spec.authors     = ['pganalyze Team']
  spec.email       = ['team@pganalyze.com']
  spec.summary     = 'Fixture gem with a native extension, used by the integration tests'
  spec.files       = Dir['lib/**/*.rb'] + Dir['ext/**/*.{rb,c}']
  spec.extensions  = ['ext/mygem/extconf.rb']
  spec.require_paths = ['lib']
end
