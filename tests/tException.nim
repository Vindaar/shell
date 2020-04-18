{.define(shellThrowException).}

import ../shell
import unittest
import strutils

suite "[shell]":
  test "[exception] throw on invalid command":
    try:
      shell:
        ls -l
        ls -z
    except ShellExecError:
      let e = cast[ShellExecError](getCurrentException())
      echo e.msg
      echo "command was: ", e.cmd
      assert e.cmd == "ls -z"
      echo "return code: ", e.retcode
      echo "error outpt: "
      for l in e.errstr.split('\n'):
        echo "  ", l
    except:
      assert false, "Execution must throw exception `ShellExecError`"
