# Package

version       = "0.4.4"
author        = "Vindaar"
description   = "A Nim mini DSL to execute shell commands"
license       = "MIT"


# Dependencies

requires "nim >= 0.19.0"

task test, "executes the tests":
  exec "nim c -d:debugShell -r tests/tShell.nim"
  exec "nim c -r tests/tException.nim"
  # execute using NimScript as well
  exec "nim e -d:debugShell -r tests/tNimScript.nims"
  # and execute PWD test, by running the nims file in another dir,
  # which itself calls the test
  when not defined(windows):
    exec "cd tests/anotherDir && nim e -r runAnotherTest.nims"

task travis, "executes the tests on travis":
  exec "nim c -d:debugShell -d:travisCI -r tests/tShell.nim"
  # execute using NimScript as well
  exec "nim e -d:debugShell -d:travisCI -r tests/tNimScript.nims"
  when not defined(windows):
    exec "cd tests/anotherDir && nim e -d:travisCI -r runAnotherTest.nims"
