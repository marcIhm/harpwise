#
#  Support for jamming with harpwise
#

def do_jamming to_handle

  fail "Internal error: case of no arguments should have been handled before" if !to_handle || to_handle.length == 0
  
  puts <<-EOTEXT

  Mode 'jamming' does not need or accept any arguments.

  Invoke:

    harpwise jamming

  (without any arguments) to learn how to proceed.


EOTEXT
  
end
