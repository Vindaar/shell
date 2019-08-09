import unittest
import ../shell

suite "[shell]":

  test "[shell] single cmd w/ StrLit":
    checkShell:
      cd "Analysis/ingrid"
    do:
      "cd Analysis/ingrid"

  test "[shell] single cmd w/ InFix":
    checkShell:
      cd Analysis/ingrid/stuff
    do:
      "cd Analysis/ingrid/stuff"

  test "[shell] single cmd w/ InFix via filename":
    checkShell:
      run test.h5
    do:
      "run test.h5"

  test "[shell] single as StrLit":
    checkShell:
      "cd Analysis"
    do:
      "cd Analysis"

  test "[shell] single cmd w/ two idents":
    checkShell:
      nimble develop
    do:
      "nimble develop"

  test "[shell] single cmd w/ prefix and StrLit":
    checkShell:
      ./reconstruction "Run123" "--out" "test.h5"
    do:
      "./reconstruction Run123 --out test.h5"

  test "[shell] single cmd w/ prefix and ident and StrLit":
    checkShell:
      ./reconstruction Run123 "--out" "test.h5"
    do:
      "./reconstruction Run123 --out test.h5"

  test "[shell] single cmd w/ prefix, ident, StrLit and InFix":
    checkShell:
      ./reconstruction Run123 "--out" test.h5
    do:
      "./reconstruction Run123 --out test.h5"

  test "[shell] single cmd w/ prefix, ident, InFix and VarTy":
    checkShell:
      ./reconstruction Run123 --out test.h5
    do:
      "./reconstruction Run123 --out test.h5"

  test "[shell] single cmd w/ prefix, ident and VarTy at the end":
    checkShell:
      ./reconstruction Run123 --out
    do:
      "./reconstruction Run123 --out"


  test "[shell] single cmd w/ tripleStrLit to escape \" ":
    checkShell:
      ./reconstruction Run123 """--out="test.h5""""
    do:
      "./reconstruction Run123 --out=\"test.h5\""

  test "[shell] command with a redirect":
    checkShell:
      echo """"test file"""" > test.txt
    do:
      "echo \"test file\" > test.txt"

  test "[shell] command with a pipe":
    checkShell:
      cat test.txt | grep """"file""""
    do:
      "cat test.txt | grep \"file\""

  test "[shell] command with a manual &&":
    checkShell:
      mkdir foo && rmdir foo
    do:
      "mkdir foo && rmdir foo"

  test "[shell] command with literal string from single word":
    checkShell:
      echo `Hallo`
    do:
      "echo \"Hallo\""

  test "[shell] command with literal string of multiple words":
    checkShell:
      echo `"Hello World!"`
    do:
      "echo \"Hello World!\""

  test "[shell] command with accent quotes for the shell":
    checkShell:
      "a=`echo Hallo`"
    do:
      "a=`echo Hallo`"

  test "[shell] view output":
    shellEcho:
      ./reconstruction Run123 --out test.h5
    check true

  test "[shell] multiple commands":
    shell:
      touch test1234567890.txt
      mv test1234567890.txt bar1234567890.txt
      rm bar1234567890.txt
    check true

  test "[shell] multiple commands in one shell call":
    checkShell:
      one:
        mkdir foo
        cd foo
        touch bar
        cd ".."
    do:
      "mkdir foo && cd foo && touch bar && cd .."

  test "[shell] combine several commands via pipe":
    checkShell:
      pipe:
        cat tests/tShell.nim
        grep test
        head -3
    do:
      "cat tests/tShell.nim | grep test | head -3"

  test "[shell] quoting a Nim symbol":
    let name = "Vindaar"
    checkShell:
      echo "Hello from" `$name`
    do:
      &"echo Hello from {name}"

  test "[shell] quoting a Nim symbol and appending to it":
    let dir = "testDir"
    checkShell:
      tar -czf `$dir`.tar.gz
    do:
      &"tar -czf {dir}.tar.gz"

  test "[shellAssign] assigning output of a shell call to a Nim var":
    var res = ""
    shellAssign:
      res = echo `hello`
    check res == "hello"

  test "[shellAssign] assigning output of a shell pipe to a Nim var":
    var res = ""
    shellAssign:
      res = pipe:
        seq 0 1 10
        tail -3
    check res == "8\n9\n10"

  test "[shell] real time output":
    shell:
      "for f in 1 2 3; do echo $f; sleep 1; done"

  test "[shellVerbose] check for exit code of wrong command":
    let res = shellVerbose:
      thisCommandDoesNotExistOnYourSystemOrThisTestWillFail
    check res[1] != 0

  test "[shellVerbose] compare output of command using shellVerbose":
    let res = shellVerbose:
      echo "Hello world!"
    check res[0] == "Hello world!"
    check res[1] == 0

  test "[shellVerbose] remove nested StmtLists":
    var toContinue = true
    template tc(cmd: untyped): untyped {.dirty.} =
      if toContinue:
        toContinue = cmd

    template shellCheck(actions: untyped): untyped =
      tc:
        let res = shellVerbose:
          actions
        res[1] == 0

    shellCheck:
      one:
        "f=hallo"
        echo $f
    check toContinue
