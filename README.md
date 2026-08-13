# bundler-source-pathext
[ ![](https://img.shields.io/gem/v/bundler-source-pathext.svg)](https://rubygems.org/gems/bundler-source-pathext)
[ ![](https://img.shields.io/gem/dt/bundler-source-pathext.svg)](https://rubygems.org/gems/bundler-source-pathext)
[ ![](https://github.com/pganalyze/bundler-path-build-ext/actions/workflows/test.yml/badge.svg)](https://github.com/pganalyze/bundler-path-build-ext/actions/workflows/test.yml)

This bundler plugin allows building local Ruby extensions that are referred to by a local path,
similar to how gems are built when they are fetched from a remote path.

Rubygems/Bundler itself unfortunately does not build local extensions automatically, making
workflows complicated that utilize gems with an extension build, as part of an application.

## Usage

In your Gemfile, replace something like `gem 'mygem', path: './folder` with:

```ruby
source './folder', type: 'pathext' do
  gem 'mygem'
end
```

Different from Rubygems, this plugin uses a modified version of
[Gem::Ext::Builder](https://github.com/ruby/rubygems/blob/master/lib/rubygems/ext/builder.rb) for
Ruby extensions with an "extconf" folder.

Rubygems installs the built binaries into the gem's `lib` folder, and keeps a second copy in the
extension install folder, but only creates that copy when it does not exist yet. For a local gem,
whose version does not change when its source does, that second copy goes stale. This plugin
installs into a single location instead, and always overwrites it: the gem's `lib` folder when
Rubygems installs extensions there (which is the default, see `install_extension_in_lib`), and the
extension install folder (`tmp/PLATFORM/GEM/RUBY_VERSION` inside the gem) otherwise. Note that
cross-compilation is not supported.

## Compatibility

Tested against Bundler 2.5, 2.6 and the current release, see the
[test workflow](.github/workflows/test.yml) for the versions that are covered.

## LICENSE

Licensed under the 3-clause BSD license, see LICENSE file for details.

Copyright (c) 2026, pganalyze Team <team@pganalyze.com>
All rights reserved.
