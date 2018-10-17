import macros
import osproc
import strutils
import elnim

proc iterateTree(cmds: NimNode): string

proc handleInfix(n: NimNode): NimNode =
  result = nnkIdentDefs.newTree()
  result.add n[1]
  result.add n[0]
  result.add n[2]

proc recurseInfix(n: NimNode): string =
  let inTree = handleInfix(n)
  if inTree[0].len > 0:
    result = iterateTree(nnkIdentDefs.newTree(inTree[0]))
  else:
    result = inTree[0].strVal
  for i in 1 ..< inTree.len:
    if inTree[i].kind == nnkIdent:
      result.add inTree[i].strVal

proc handlePrefix(n: NimNode): string =
  var m = copy(n)
  result = m[0].strVal
  m.del(0)
  result.add iterateTree(m)

proc handleVarTy(n: NimNode): string =
  result = "out"
  if n.len > 0:
    result.add " " & iterateTree(nnkIdentDefs.newTree(n[0]))

proc iterateTree(cmds: NimNode): string =
  var subCmds: seq[string]
  for cmd in cmds:
    case cmd.kind
    of nnkCommand:
      subCmds.add iterateTree(cmd)
    of nnkPrefix:
      subCmds.add handlePrefix(cmd)
    of nnkIdent:
      subCmds.add cmd.strVal
    of nnkDotExpr:
      # TODO: still handled via `repr`!
      subCmds.add cmd.repr
    of nnkStrLit, nnkTripleStrLit:
      #echo "Is str lit ", cmd.repr
      subCmds.add cmd.strVal
    of nnkVarTy:
      subCmds.add handleVarTy(cmd)
    of nnkInfix:
      subCmds.add recurseInfix(cmd)
    else:
      error("Unsupported node kind: " & $cmd.kind & " for command " & cmd.repr &
        ". Consider putting offending part into \" \".")

  result = subCmds.mapconcat()

proc execShell*(cmd: string) =
  ## wrapper around `execCmdEx`, which calls the commands and handles
  ## return values
  echo cmd
  let (outp, errC) = execCmdEx(cmd)
  if errC != 0:
    echo "Error calling ", cmd, " with code ", errC
  if outp.len > 0:
    echo "Output for cmd: ", cmd
    echo "\t", outp

proc genShellCmds(cmds: NimNode): seq[string] =
  ## the proc that actually generates the shell commands
  ## from the given statements
  # iterate over all commands in the command list
  for cmd in cmds:
    case cmd.kind
    of nnkCommand:
      result.add iterateTree(cmd)
    of nnkStrLit:
      result.add cmd.strVal
    of nnkPrefix:
      result.add iterateTree(nnkIdentDefs.newTree(cmd))
    else:
      error("Unsupported node kind: " & $cmd.kind & " for command " & cmd.repr &
        ". Consider putting offending part into \" \".")

macro shell*(cmds: untyped): untyped =
  ## a mini DSL to write shell commands in Nim. Some constructs are not
  ## implemented. If in doubt, put (parts of) the command into " "
  ## The command is echoed before it is run.
  ## If there is output, the output is echoed.
  ## If the return value of the command is non zero the error is echoed.
  expectKind cmds, nnkStmtList
  result = newStmtList()
  let shCmds = genShellCmds(cmds)

  for cmd in shCmds:
    result.add quote do:
      execShell(`cmd`)

  when defined(debugShell):
    echo result.repr

macro shellEcho*(cmds: untyped): untyped =
  ## a helper macro around the proc that generates the shell commands
  ## to check whether the commands are as expected
  expectKind cmds, nnkStmtList
  let shCmds = genShellCmds(cmds)
  for cmd in shCmds:
    echo cmd

macro checkShell*(cmds: untyped, exp: untyped): untyped =
  ## a wrapper around the shell macro, which can calls `unittest.check` to
  ## check whether construction of the commands works as expected
  expectKind cmds, nnkStmtList

  let shCmds = genShellCmds(cmds)

  if exp.kind == nnkStmtList:
    let checkCommand = shCmds[0]
    result = quote do:
      check `checkCommand` == `exp[0]`

  when defined(debugShell):
    echo result.repr
