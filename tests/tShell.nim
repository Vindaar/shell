import unittest
import ../shell
import strutils

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

  test "[shell] single cmd with `nnkAsgn`":
    checkShell:
      ./reconstruction Run123 --out=test.h5 --foo
    do:
      "./reconstruction Run123 --out=test.h5 --foo"

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

  when not defined(windows):
    ## this test does not work on windows, since the commands don't exist
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
      echo "Hello from" ($name)
    do:
      &"echo Hello from {name}"

  test "[shell] quoting a Nim symbol and appending to it using dotExpr":
    let dir = "testDir"
    checkShell:
      tar -czf ($dir).tar.gz
    do:
      &"tar -czf {dir}.tar.gz"

  test "[shell] unintuitive: quoting a Nim symbol (), appending string":
    ## This is a rather unintuitive side effect of the way the Nim parser works.
    ## Unfortunately appending a string literal to a quote via `()` will result
    ## in a space between the quoted identifier and the string literal.
    ## See the test case below, which quotes everything via `()`.
    let dir = "testDir"
    checkShell:
      tar -czf ($dir)".tar.gz"
    do:
      &"tar -czf {dir} .tar.gz"

  test "[shell] quoting a Nim symbol () and appending string inside the ()":
    let dir = "testDir"
    checkShell:
      tar -czf ($dir".tar.gz")
    do:
      &"tar -czf {dir}.tar.gz"

  test "[shell] quoting a Nim expression () and appending string inside the ()":
    let pdf = "test.pdf"
    checkShell:
      pdfcrop "--margins '5 5 5 5'" ($pdf) ($(pdf.replace(".pdf",""))"_cropped.pdf")
    do:
      &"pdfcrop --margins '5 5 5 5' {pdf} {pdf.replace(\".pdf\",\"\")}_cropped.pdf"

  test "[shell] quoting a Nim symbol and appending it to a string without space":
    let outname = "test.h5"
    checkShell:
      ./test "--out="($outname)
    do:
      &"./test --out={outname}"

  test "[shell] quoting a Nim symbol and appending it within `()`":
    let outname = "test.h5"
    checkShell:
      ./test ("--out="$outname)
    do:
      &"./test --out={outname}"

  test "[shell] quoting a Nim symbol and appending it within `()` with a space":
    ## NOTE: while this works, it is not the recommended way for clarity!
    let outname = "test.h5"
    checkShell:
      ./test ("--out" $outname)
    do:
      &"./test --out {outname}"

  test "[shell] quoting a Nim symbol and appending it to a string with space":
    let outname = "test.h5"
    checkShell:
      ./test "--out" ($outname)
    do:
      &"./test --out {outname}"

  test "[shell] quoting a Nim symbol with tuple fields":
    const run = (name: "Run_240_181021-14-54", outName: "run_240.h5")
    checkShell:
      ./test "--in" ($run.name) "--out" ($(run.outName))
    do:
      &"./test --in {run.name} --out {run.outName}"

  test "[shell] quoting a Nim symbol with tuple fields, appending to string":
    const run = (name: "Run_240_181021-14-54", outName: "run_240.h5")
    checkShell:
      ./test ("--in="$(run.name)) ("--out="$(run.outName))
    do:
      &"./test --in={run.name} --out={run.outName}"

  test "[shell] quoting a Nim symbol with tuple fields, appending to string without parens":
    const run = (name: "Run_240_181021-14-54", outName: "run_240.h5")
    checkShell:
      ./test ("--in="$run.name) ("--out="$run.outName)
    do:
      &"./test --in={run.name} --out={run.outName}"

  test "[shell] quoting a Nim expression with obj fields":
    type
      TestObj = object
        name: string
        val: float
    let obj = TestObj(name: "test", val: 5.5)
    checkShell:
      ./test ("--in="$obj.name) ("--val="$(obj.val))
    do:
      &"./test --in={obj.name} --val={(obj.val)}"

  test "[shell] quoting a Nim expression with proc call":
    # sometimes calling a function on an identifier is useful, e.g. to extract
    # a filename
    proc extractFilename(s: string): string =
      result = s[^11 .. ^1]
    let path = "/some/user/path/toAFile.txt"
    checkShell:
      ./test ("--in="$(path.extractFilename))
    do:
      &"./test --in={path.extractFilename}"

  test "[shell] quoting a Nim expression, prepending and appending to it":
    let name = "foo"
    checkShell:
      Rscript -e ("rmarkdown::render('"$name"')")
    do:
      &"Rscript -e rmarkdown::render('foo')"

  test "[shell] quoting a Nim expression, prepending and appending to it, literal string":
    let name = "foo"
    checkShell:
      Rscript -e ("\"rmarkdown::render('"$name"""')"""")
    do:
      &"Rscript -e \"rmarkdown::render('foo')\""

  test "[shell] quoting a Nim expression without anything else":
    let myCmd = "runMe"
    checkShell:
      ($myCmd)
    do:
      $myCmd

  ## these tests don't work on windows, since the commands don't exist
  test "[shellAssign] assigning output of a shell call to a Nim var":
    var res = ""
    shellAssign:
      res = echo `hello`
    check res == "hello"

  when not defined(windows):
    ## `pipe` does not work on windows
    test "[shellAssign] assigning output of a shell pipe to a Nim var":
      var res = ""
      shellAssign:
        res = pipe:
          seq 0 1 10
          tail -3
      when not defined(travisCI):
        # test is super flaky on travis. Often thee 10 is missing?!
        check res.multiReplace([("\n", "")]) == "8910"

  test "[shellAssign] assigning output from shell to a variable while quoting a Nim var":
    var res = ""
    let name1 = "Lucian"
    let name2 = "Markus"
    shellAssign:
      res = echo "Hello " ($name1) "and" ($name2)
    check res == "Hello Lucian and Markus"

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

  when not defined(windows):
    ## `one` command does not work on windows
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

  test "[shellVerbose] check commands are not run after failure":
    let res = shellVerbose:
      echo runBrokenCommand
      thisCommandDoesNotExistOnYourSystemOrThisTestWillFail
      echo Hello
    check res[1] != 0
    check res[0].startsWith("runBrokenCommand")

  when not defined(windows):
    ## stderr redirect does not work on windows?
    test "[shellVerboseErr] check stderr output":
      let test = "test"
      let (res, err, _) = shellVerboseErr:
        echo ($test)
        echo ($test) >&2

      doAssert test == res
      doAssert test == err

  test "[shellVerboseErr] setting debug config works":
    let test = "test"
    let (res, err, _) = shellVerboseErr {dokOutput}:
      echo ($test)

    doAssert test == res

  test "[shellVerbose] change process options":
    let (res, err) = shellVerbose(options = {poEvalCommand}):
      echo "Hello World"
    check res == "Hello World"
