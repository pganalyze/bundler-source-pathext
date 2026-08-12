require 'mkmf'

# Recorded so the tests can check which build args the extension was built with
File.write(File.join(__dir__, 'build_args.txt'), ARGV.join(' '))

create_makefile('mygem/mygem_native')
