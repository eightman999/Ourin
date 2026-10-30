MRuby::Build.new do |conf|
  conf.toolchain :clang
  conf.gembox 'default'
  conf.cc.flags << '-mmacosx-version-min=13.0'
  conf.cc.defines << 'MRB_UTF8_STRING'
end
