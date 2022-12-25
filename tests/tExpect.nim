import ../shell
import std / unittest

# only run on linux due to the tExpect shell script (and not any platform bindings
# of the `expect` support)
when defined(linux):
  block:
    var res = ""
    shellAssign:
      res = "./tests/tExpect.sh"
      expect: "Your name?"
      send: "Vindaar"
    check res == """Hello world. Your name?
Your name is Vindaar"""

  block:
    # now try without the `expect`
    var res = ""
    shellAssign:
      res = "./tests/tExpect.sh"
      send: "Vindaar"
    check res == """Hello world. Your name?
Your name is Vindaar"""
