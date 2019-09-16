import macros
when not defined(NimScript):
  import osproc, streams, os
import strutils, strformat
export strformat

type
  InfixKind = enum
    ifSlash = "/"
    ifBackSlash = "\\"
    ifGreater = ">"
    ifSmaller = "<"
    ifDash = "-"
    ifPipe = "|"
    ifAnd = "&&"

proc iterateTree(cmds: NimNode): string

proc replaceInfixKind(ifKind: InfixKind): string =
  case ifKind
  of ifSlash, ifBackSlash:
    result = $ifKind
  else:
    result = " " & $ifKind & " "

proc handleInfix(n: NimNode): NimNode =
  ## reorder the tree of the infix
  ## TODO: we could just use `unpackInfix` ?
  result = nnkIdentDefs.newTree()
  result.add n[1]
  result.add n[0]
  result.add n[2]

proc handleDotExpr(n: NimNode): string =
  ## string value for a dot expr
  var stmts = nnkIdentDefs.newTree()
  stmts.add n[0]
  stmts.add ident(".")
  stmts.add n[1]
  for el in stmts:
    result.add iterateTree(nnkIdentDefs.newTree(el))

proc recurseInfix(n: NimNode): string =
  ## replace infix tree by an identDefs tree in correct order
  ## and a string node in place of the previous "infixed" symbol
  var m = copy(n)
  let ifKind = parseEnum[InfixKind](m[0].strVal)
  # replace the infix symbol
  m[0] = newLit(replaceInfixKind(ifKind))
  let inTree = handleInfix(m)
  for el in inTree:
    result.add iterateTree(nnkIdentDefs.newTree(el))

proc handlePrefix(n: NimNode): string =
  ## handle `nnkPrefix`
  var m = copy(n)
  result = m[0].strVal
  m.del(0)
  result.add iterateTree(m)

proc handleVarTy(n: NimNode): string =
  ## varTy replaces our `out` with a `var`. Replace manually
  result = "out"
  if n.len > 0:
    result.add " " & iterateTree(nnkIdentDefs.newTree(n[0]))

proc rawString(n: NimNode): string =
  ## converts an identifier that is given in accented quotes to
  ## a raw string literal in quotation marks
  expectKind n, nnkAccQuoted
  result = "\"" & n[0].strVal & "\""

proc nimSymbol(n: NimNode): string =
  ## converts the identifier given in accented quotes to a Nim symbol
  ## quoted in `{}` using strformat
  expectKind n, nnkAccQuoted
  if eqIdent(n[0], "$"):
    result = "{" & n[1].strVal & "}"
  else:
    error("Unsupported symbol in accented quotes: " & $n.repr)

proc iterateTree(cmds: NimNode): string =
  ## main proc which iterates over tree and assigns assigns the correct
  ## strings to `subCmds` depending on NimNode kind
  var subCmds: seq[string]
  var nimSymbolInserted = false
  for cmd in cmds:
    case cmd.kind
    of nnkCommand:
      subCmds.add iterateTree(cmd)
    of nnkPrefix:
      subCmds.add handlePrefix(cmd)
    of nnkIdent:
      subCmds.add cmd.strVal
    of nnkDotExpr:
      subCmds.add handleDotExpr(cmd)
    of nnkStrLit, nnkTripleStrLit:
      subCmds.add cmd.strVal
    of nnkIntLit, nnkFloatLit:
      subCmds.add cmd.repr
    of nnkVarTy:
      subCmds.add handleVarTy(cmd)
    of nnkInfix:
      subCmds.add recurseInfix(cmd)
    of nnkAccQuoted:
      # handle accented quotes. Allows to either have the content be put into
      # a raw string literal, or if prefixed by `$` assumed to be a Nim symbol
      case cmd.len
      of 1:
        subCmds.add rawString(cmd)
      of 2:
        subCmds.add nimSymbol(cmd)
        nimSymbolInserted = true
      else:
        error("Unsupported quoting: " & $cmd.kind & " for command " & cmd.repr)
    else:
      error("Unsupported node kind: " & $cmd.kind & " for command " & cmd.repr &
        ". Consider putting offending part into \" \".")

  result = subCmds.join(" ")

proc concatCmds(cmds: seq[string], sep = " && "): string =
  ## concat commands to single string, by default via `&&`
  result = cmds.join(sep)

proc asgnShell*(cmd: string): tuple[output: string, exitCode: int] =
  ## wrapper around `execCmdEx`, which returns the output of the shell call
  ## as a string (stripped of `\n`)
  when not defined(NimScript):
    let pid = startProcess(cmd, options = {poEvalCommand})
    let outStream = pid.outputStream
    var line = ""
    var res = ""
    while pid.running:
      try:
        let streamRes = outStream.readLine(line)
        if streamRes:
          echo "shell> ", line
          res = res & "\n" & line
        else:
          # should mean stream is finished, i.e. process stoped
          echo "line was ", line.len
          sleep 10
          doAssert not pid.running
          break
      except IOError, OSError:
        # outstream died on us?
        doAssert outStream.isNil
        break
    let exitCode = pid.peekExitCode
    if exitCode != 0:
      # add error stream to output
      let err = pid.errorStream
      res.add err.readAll()
      err.close()
    pid.close()
    result = (output: res, exitCode: exitCode)
  else:
    # prepend the NimScript called command by current directory
    let nscmd = &"cd {getCurrentDir()} && " & cmd
    result = gorgeEx(nscmd, "", "")
  result[0] = result[0].strip(chars = {'\n'})

proc execShell*(cmd: string): tuple[output: string, exitCode: int] =
  ## wrapper around `asgnShell`, which calls the commands and handles
  ## return values.
  echo "shellCmd: ", cmd
  result = asgnShell(cmd)
  when defined(NimScript):
    # output of child process is already echoed on the fly for non NimScript
    # usage
    if result[0].len > 0:
      for line in splitLines(result[0]):
        echo "shell> ", line

proc flattenCmds(cmds: NimNode): NimNode =
  ## removes nested StmtLists, if any
  case cmds.kind
  of nnkStmtList:
    if cmds.len == 1 and cmds[0].kind == nnkStmtList:
      result = flattenCmds(cmds[0])
    else:
      result = cmds
  else:
    result = cmds

proc genShellCmds(cmds: NimNode): seq[string] =
  ## the proc that actually generates the shell commands
  ## from the given statements
  # first strip potential nested StmtLists from input
  let flatCmds = flattenCmds(cmds)

  # iterate over all commands in the command list
  for cmd in flatCmds:
    case cmd.kind
    of nnkCall:
      if eqIdent(cmd[0], "one"):
        # in this case call this proc on content
        let oneCmd = genShellCmds(cmd[1])
        # and concat them to a valid concat of shell calls
        result.add concatCmds(oneCmd)
      elif eqIdent(cmd[0], "pipe"):
        # in this case call this proc on content
        let pipeCmd = genShellCmds(cmd[1])
        # and concat them to a valid string of piped commands
        result.add concatCmds(pipeCmd, sep = " | ")
    of nnkCommand:
      result.add iterateTree(cmd)
    of nnkIdent, nnkStrLit, nnkTripleStrLit:
      result.add cmd.strVal
    of nnkPrefix, nnkAccQuoted:
      result.add iterateTree(nnkIdentDefs.newTree(cmd))
    else:
      error("Unsupported node kind: " & $cmd.kind & " for command " & cmd.repr &
        ". Consider putting offending part into \" \".")

proc nilOrQuote(cmd: string): NimNode =
  ## either returns a string literal node if the given command does
  ## not contain curly brackets (indicating a Nim symbol is quoted)
  ## or prefix a `&` to call strformat
  if "{" in cmd and "}" in cmd:
    result = nnkPrefix.newTree(ident"&", newLit(cmd))
  else:
    result = newLit(cmd)

macro shellVerbose*(cmds: untyped): untyped =
  ## a mini DSL to write shell commands in Nim. Some constructs are not
  ## implemented. If in doubt, put (parts of) the command into " "
  ## The command is echoed before it is run. It is prefixed by `shellCmd: `.
  ## If there is output, the output is echoed. Each successive line of the
  ## output is prefixed by `shell> `.
  ## If multiple commands are run in succession (i.e. multiple statements in
  ## the macro body) and one command returns a non-zero exit code, the following
  ## commands will not be run. Instead a warning message will be shown.
  ## For usage with NimScript the output can only be echoed after the
  ## call has finished.
  ## The macro returns a tuple of:
  ## - output: string <- output of the shell command to stdout
  ## - exitCode: int <- the exit code as an integer
  expectKind cmds, nnkStmtList
  result = newStmtList()
  let shCmds = genShellCmds(cmds)

  # we use two temporary variables. One to store total output of all commands
  # and the other to store the last exitCode.
  let exCodeSym = genSym(nskVar, "exitCode")
  let outputSym = genSym(nskVar, "outputStr")
  result.add quote do:
    var `outputSym` = ""
    var `exCodeSym`: int

  for cmd in shCmds:
    let qCmd = nilOrQuote(cmd)
    result.add quote do:
      # use the exit code to determine if next command should be run
      if `exCodeSym` == 0:
        let tmp = execShell(`qCmd`)
        `outputSym` = `outputSym` & tmp[0]
        `exCodeSym` = tmp[1]
      else:
        echo "Skipped command `" & `qCmd` & "` due to failure in previous command!"

  # put everything in a block and return the result
  result = quote do:
    block:
      `result`
      (`outputSym`, `exCodeSym`)

  when defined(debugShell):
    echo result.repr

macro shell*(cmds: untyped): untyped =
  ## a mini DSL to write shell commands in Nim. Some constructs are not
  ## implemented. If in doubt, put (parts of) the command into " "
  ## The command is echoed before it is run. It is prefixed by `shellCmd: `.
  ## If there is output, the output is echoed. Each successive line of the
  ## output is prefixed by `shell> `.
  ## For usage with NimScript the output can only be echoed after the
  ## call has finished.
  ## The exit code of the command is dropped. If you wish to inspect
  ## the exit code, use `shellVerbose` above.
  result = quote do:
    discard shellVerbose(`cmds`)

macro shellEcho*(cmds: untyped): untyped =
  ## a helper macro around the proc that generates the shell commands
  ## to check whether the commands are as expected
  ## It echoes the commands at compile time (the representation of the
  ## command) and also the resulting string (taking into account potential)
  ## Nim symbol quoting at run time
  expectKind cmds, nnkStmtList
  result = newStmtList()
  let shCmds = genShellCmds(cmds)
  for cmd in shCmds:
    let qCmd = nilOrQuote(cmd)
    # echo representation at compile time
    echo qCmd.repr
    # and echo
    result.add quote do:
      echo `qCmd`

macro checkShell*(cmds: untyped, exp: untyped): untyped =
  ## a wrapper around the shell macro, which can calls `unittest.check` to
  ## check whether construction of the commands works as expected
  expectKind cmds, nnkStmtList

  let shCmds = genShellCmds(cmds)

  if exp.kind == nnkStmtList:
    let checkCommand = nilOrQuote(shCmds[0])
    when not defined(NimScript):
      result = quote do:
        check `checkCommand` == `exp[0]`
    else:
      result = quote do:
        doAssert `checkCommand` == `exp[0]`
  when defined(debugShell):
    echo result.repr

macro shellAssign*(cmd: untyped): untyped =
  expectKind cmd, nnkStmtList
  expectKind cmd[0], nnkAsgn
  doAssert cmd[0].len == 2, "Only a single assignment is allowed!"

  ## in this case assume node 0 is Nim identifier to which we wish
  ## to assign value of rest of the nodes
  let nimSym = cmd[0][0]
  # node 1 is the shell call we make
  let cmds = nnkIdentDefs.newTree(cmd[0][1])
  let shCmd = genShellCmds(cmds)[0]

  result = quote do:
    `nimSym` = asgnShell(`shCmd`)[0]

  when defined(debugShell):
    echo result.repr
