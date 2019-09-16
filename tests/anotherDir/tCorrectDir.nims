import ../../shell
import strutils

block:
  # check that current working directory is indeed the one we call from
  var res = ""
  shellAssign:
    res = pwd
  # result should be the directory "anotherDir" and ``not!`` ``shell``, since
  # the test code is run from this directory via the `runAnotherTest.nims` file
  doAssert res.endsWith("anotherDir")
