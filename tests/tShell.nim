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

  test "[shell] view output":
    shellEcho:
      ./reconstruction Run123 --out test.h5
    check true

  test "[shell] multiple commands":
    shell:
      touch test.txt
      cp test.txt abc.txt
      rm test.txt
      rm test.txt
