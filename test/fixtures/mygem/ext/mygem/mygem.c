#include <ruby.h>

/* The tests rewrite the marker string below to check that a changed extension
   gets rebuilt, even though the gem version stays the same. */
void Init_mygem_native(void) {
  VALUE mod = rb_define_module("MyGemNative");
  rb_define_const(mod, "BUILT", rb_str_new_cstr("built"));
}
