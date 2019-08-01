# Package

version       = "0.1.0"
author        = "Vindaar"
description   = "A Nim mini DSL to execute shell commands"
license       = "MIT"


# Dependencies

requires "nim >= 0.19.0"

task test, "executes the tests":
  exec "nim c -d:debugShell -r tests/tShell.nim"
  # execute using NimScript as well
  exec "nim e -d:debugShell -r tests/tNimScript.nims"
