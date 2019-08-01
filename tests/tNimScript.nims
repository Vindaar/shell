import ../shell

checkShell:
  cd "Analysis/ingrid"
do:
  "cd Analysis/ingrid"

checkShell:
  cd Analysis/ingrid/stuff
do:
  "cd Analysis/ingrid/stuff"

checkShell:
  run test.h5
do:
  "run test.h5"

checkShell:
  "cd Analysis"
do:
  "cd Analysis"

checkShell:
  nimble develop
do:
  "nimble develop"

checkShell:
  ./reconstruction "Run123" "--out" "test.h5"
do:
  "./reconstruction Run123 --out test.h5"

checkShell:
  ./reconstruction Run123 "--out" "test.h5"
do:
  "./reconstruction Run123 --out test.h5"

checkShell:
  ./reconstruction Run123 "--out" test.h5
do:
  "./reconstruction Run123 --out test.h5"

checkShell:
  ./reconstruction Run123 --out test.h5
do:
  "./reconstruction Run123 --out test.h5"

checkShell:
  ./reconstruction Run123 --out
do:
  "./reconstruction Run123 --out"


checkShell:
  ./reconstruction Run123 """--out="test.h5""""
do:
  "./reconstruction Run123 --out=\"test.h5\""

checkShell:
  echo """"test file"""" > test.txt
do:
  "echo \"test file\" > test.txt"

checkShell:
  cat test.txt | grep """"file""""
do:
  "cat test.txt | grep \"file\""

checkShell:
  mkdir foo && rmdir foo
do:
  "mkdir foo && rmdir foo"

checkShell:
  echo `Hallo`
do:
  "echo \"Hallo\""

checkShell:
  echo `"Hello World!"`
do:
  "echo \"Hello World!\""

checkShell:
  "a=`echo Hallo`"
do:
  "a=`echo Hallo`"

shellEcho:
  ./reconstruction Run123 --out test.h5

shell:
  touch test1234567890.txt
  mv test1234567890.txt bar1234567890.txt
  rm bar1234567890.txt

checkShell:
  one:
    mkdir foo
    cd foo
    touch bar
    cd ".."
do:
  "mkdir foo && cd foo && touch bar && cd .."

checkShell:
  pipe:
    cat tests/tShell.nim
    grep test
    head -3
do:
  "cat tests/tShell.nim | grep test | head -3"

let name = "Vindaar"
checkShell:
  echo "Hello from" `$name`
do:
  &"echo Hello from {name}"

let dir = "testDir"
checkShell:
  tar -czf `$dir`.tar.gz
do:
  &"tar -czf {dir}.tar.gz"

block:
  var res = ""
  shellAssign:
    res = echo `hello`
  doAssert res == "hello"

block:
  var res = ""
  shellAssign:
    res = pipe:
      seq 0 1 10
      tail -3
  doAssert res == "8\n9\n10"

block:
  let ret = shellVerbose:
    "for f in 1 2 3; do echo $f; sleep 1; done"
  doAssert ret[0] == "1\n2\n3", "was " & $ret[0]

echo "All tests passed using NimScript!"
