# Package

version       = "0.1.0"
author        = "Vindaar"
description   = "A Nim mini DSL to execute shell commands"
license       = "MIT"


# Dependencies

requires "nim >= 0.19.0"
requires "https://github.com/kaushalmodi/elnim#head"

task test, "executes the tests":
  exec "nim c -d:debugShell -r tests/tShell.nim"
