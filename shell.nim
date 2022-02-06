import macros
when not defined(NimScript):
  import osproc, streams, os
  export osproc
else:
  type
    # dummy enum, which has no effect on NimScript
    ProcessOption* = enum
      poEchoCmd, poUsePath, poEvalCommand, poStdErrToStdOut, poParentStreams,
      poInteractive, poDaemon
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

  DebugOutputKind* = enum
    dokCommand
    dokError
    dokOutput
    dokRuntime

type
  ShellExecError* = ref object of CatchableError
    cmd*: string ## Command that returned non-zero exit code
    cwd*: string ## Absolute path of initial command execution directory
    retcode*: int ## Exit code
    errstr*: string ## Stderr for command
    outstr*: string ## Stdout for command

const defaultDebugConfig: set[DebugOutputKind] =
  block:
    var config: set[DebugOutputKind] = {
      dokOutput, dokError, dokCommand, dokRuntime
    }

    when defined shellNoDebugOutput:
      config = config - {dokOutput}

    when defined shellNoDebugError:
      config = config - {dokError}

    when defined shellNoDebugCommand:
      config = config - {dokCommand}

    when defined shellNoDebugRuntime:
      config = config - {dokRuntime}

    when defined shellThrowException:
      config = {}

    config

when defined(windows):
  const defaultProcessOptions: set[ProcessOption] = {poStdErrToStdOut, poEvalCommand, poDaemon, poUsePath}
else:
  const defaultProcessOptions: set[ProcessOption] = {poStdErrToStdOut, poEvalCommand}
# this default is used for `shellVerboseErr` where we do ``not`` want to combine stdout
# and stderr.
const defaultProcessOptionsErr: set[ProcessOption] = {poEvalCommand}

proc stringify(cmd: NimNode): string
proc iterateTree(cmds: NimNode, joinBy = " "): string

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

proc handleQuote(n: NimNode): NimNode =
  ## reconstruct a tree with `$` prefix / infix replaced by
  ## curly of repr
  proc addArg(res: var NimNode, n: NimNode) =
    let arg = handleQuote(n)
    case arg.kind
    of nnkIdentDefs, nnkCommand:
      res.add nnkCurly.newTree(arg[0])
      res.add arg[1]
    else:
      res.add nnkCurly.newTree(arg)

  if n.len == 0:
    result = n # keep node
  else:
    # if tree, modify from existing form replacing `$` calls by `nnkCurly`
    case n.kind
    of nnkPrefix:
      if eqIdent(n[0], "$"): # if `$` prefix, rewrite to reordered nnkIdentDefs
        result = nnkIdentDefs.newTree()
        result.addArg(n[1])
      else:
        result = n
    of nnkCallStrLit:
      # `$foo"someString"` rewrite to ident defs
      result = nnkIdentDefs.newTree(handleQuote(n[0]), handleQuote(n[1]))
    of nnkCommand:
      # `"someString"$foo` rewrite to ident defs
      result = nnkCommand.newTree(handleQuote(n[0]), handleQuote(n[1]))
    of nnkInfix:
      if eqIdent(n[0], "$"):
        # reorder infix and rewrite as nnkIdentDefs
        result = nnkIdentDefs.newTree()
        result.add handleQuote(n[1])
        result.addArg(n[2])
      else:
        result = n
    else:
      # keep as is, possibly replace children
      result = newTree(n.kind)
      for ch in n:
        result.add handleQuote(ch)

proc parensUnquotePrefix(n: NimNode): string =
  let res = handleQuote(n)
  result = stringify(res)

proc nimSymbol(n: NimNode, useParens: static bool): string =
  ## converts the identifier given in accented quotes to a Nim symbol
  ## quoted in `{}` using strformat
  when declared(oldQuote):
    expectKind n, nnkAccQuoted
    if eqIdent(n[0], "$"):
      result = "{" & n[1].strVal & "}"
    else:
      error("Unsupported symbol in accented quotes: " & $n.repr)
  else:
    expectKind n, nnkPar
    result = parensUnquotePrefix(n[0])

proc handleCall(n: NimNode): string =
  ## converts the given `NimNode` representing a call to a string. The call
  ## corresponds to usage of `()`, thus a quoting of a nim identifier.
  ## Specifically, this corresponds to the case in which some identifier
  ## or string literal appears right before a quoted nim identifier, so that
  ## the value of the quoted identifier is placed right after the first
  ## argument.
  ## Assuming `outname` defines a string with value `test.h5`, then:
  ## Call
  ##   StrLit "--out="
  ##   Prefix
  ##     Ident "$"
  ##     Ident "outname"
  ## -> "--out=test.h5"
  expectKind n[1], nnkPrefix
  result = stringify(n[0]) & parensUnquotePrefix(n[1])

proc stringify(cmd: NimNode): string =
  ## Handles the stringification of a single `NimNode` according to its
  ## `NimNodeKind`.
  case cmd.kind
  of nnkCommand:
    result = iterateTree(cmd)
  of nnkCall:
    # call may appear when quoting with `()` without space after previous
    # element
    result = handleCall(cmd)
  of nnkPrefix:
    result = handlePrefix(cmd)
  of nnkIdent:
    result = cmd.strVal
  of nnkDotExpr:
    result = handleDotExpr(cmd)
  of nnkStrLit, nnkTripleStrLit, nnkRStrLit:
    result = cmd.strVal
  of nnkCallStrLit:
    result = stringify(cmd[0]) & stringify(cmd[1])
  of nnkIntLit, nnkFloatLit:
    result = cmd.repr
  of nnkVarTy, nnkMutableTy:
    # `nnkMutableTy` required for https://github.com/nim-lang/Nim/issues/15751
    result = handleVarTy(cmd)
  of nnkInfix:
    result = recurseInfix(cmd)
  of nnkCurly:
    doAssert cmd.len == 1
    result = "{" & cmd[0].repr & "}"
  of nnkIdentDefs:
    result = iterateTree(cmd, joinBy = "")
  of nnkAccQuoted:
    # handle accented quotes. Allows to either have the content be put into
    # a raw string literal, or if prefixed by `$` assumed to be a Nim symbol
    case cmd.len
    of 1:
      result = rawString(cmd)
    of 2:
      when declared(oldQuote):
        result = nimSymbol(cmd, useParens = false)
      else:
        error("API change: for quoting use ()! Compile with -d:oldQuote for grace period." &
              "Offending command: " & cmd.repr)
    else:
      error("Unsupported quoting: " & $cmd.kind & " for command " & cmd.repr)
  of nnkPar:
    when not declared(oldQuote):
      result = nimSymbol(cmd, useParens = true)
    else:
      error("Quoting via () only allowed if compiled without -d:oldQuote!" &
        "Relevant command: " & cmd.repr)
  else:
    error("Unsupported node kind: " & $cmd.kind & " for command " & cmd.repr &
      ". Consider putting offending part into \" \".")

proc iterateTree(cmds: NimNode, joinBy = " "): string =
  ## main proc which iterates over tree and assigns assigns the correct
  ## strings to `subCmds` depending on NimNode kind
  var subCmds: seq[string]
  for cmd in cmds:
    subCmds.add stringify(cmd)
  result = subCmds.join(joinBy)

proc concatCmds(cmds: seq[string], sep = " && "): string =
  ## concat commands to single string, by default via `&&`
  result = cmds.join(sep)

proc asgnShell*(
  cmd: string,
  debugConfig: set[DebugOutputKind] = defaultDebugConfig,
  options: set[ProcessOption] = defaultProcessOptions
              ): tuple[output, error: string, exitCode: int] =
  ## wrapper around `execCmdEx`, which returns the output of the shell call
  ## as a string (stripped of `\n`)
  when not defined(NimScript):
    when defined(windows):
      var pid: Process
      try:
        pid = startProcess(cmd, options = options)
      except OSError as e:
        let exitCode = 1
        let err = e.msg
        return (output: "", error: err, exitCode: exitCode)
    else:
      let pid = startProcess(cmd, options = options)

    let outStream = pid.outputStream
    var line = ""
    var res = ""
    while pid.running:
      try:
        let streamRes = outStream.readLine(line)
        if streamRes:
          if dokOutput in debugConfig:
            echo "shell> ", line
          res = res & "\n" & line
        else:
          # should mean stream is finished, i.e. process stoped
          sleep 10
          doAssert not pid.running
          break
      except IOError, OSError:
        # outstream died on us?
        doAssert outStream.isNil
        break

    if not outStream.atEnd():
      if dokOutput in debugConfig:
        let rem = outStream.readAll()
        res &= rem
        for line in rem.split("\n"):
          echo "shell> ", line
      else:
        res &= outStream.readAll()

    let exitCode = pid.peekExitCode

    # Zero exit code does not guarantee that there will be nothing in
    # stderr.
    let err = pid.errorStream
    let errorText = err.readAll()

    if exitCode != 0:
      if dokRuntime in debugConfig:
        echo "Error when executing: ", cmd

      if dokError in debugConfig:
        for line in errorText.split("\n"):
          echo "err> ", line

    pid.close()
    result = (output: res, error: errorText, exitCode: exitCode)

  else:
    # prepend the NimScript called command by current directory
    let nscmd = &"cd {getCurrentDir()} && " & cmd
    let (res, code) = gorgeEx(nscmd, "", "")
    result.output = res
    result.exitCode = code
  result.output = result.output.strip(chars = {'\n'})
  result.error = result.error.strip(chars = {'\n'})

proc execShell*(
  cmd: string,
  debugConfig: set[DebugOutputKind] = defaultDebugConfig,
  options: set[ProcessOption] = defaultProcessOptions
              ): tuple[output, error: string, exitCode: int] =
  ## wrapper around `asgnShell`, which calls the commands and handles
  ## return values.
  if dokCommand in debugConfig:
    echo "shellCmd: ", cmd

  let cwd = getCurrentDir()
  result = asgnShell(cmd, debugConfig, options)

  if dokOutput in debugConfig:
    when defined(NimScript):
      # output of child process is already echoed on the fly for non NimScript
      # usage
      if result[0].len > 0:
        for line in splitLines(result[0]):
          echo "shell> ", line

  when defined shellThrowException:
    if result.exitCode != 0:
      raise ShellExecError(
        msg: "Command " & cmd & " exited with non-zero code",
        cmd: cmd,
        cwd: cwd,
        retcode: result.exitCode,
        errstr: result.error,
        outstr: result.output
      )

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
    of nnkPar:
      result.add cmd.stringify
    of nnkAsgn:
      # handle first child, then second
      let lhs = stringify(cmd[0])
      let rhs = stringify(cmd[1])
      result.add concatCmds(@[lhs, rhs], sep = "=")
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

proc shellVerboseImpl(debugConfig: NimNode,
                      options: NimNode,
                      combineOutAndErr: bool,
                      cmds: NimNode): NimNode =
  ## This is the compile time proc, which creates the actual code of the shell macro.
  ## Depending on `combineOutAndErr` it returns either a 2 tuple or a 3 tuple.
  expectKind cmds, nnkStmtList
  result = newStmtList()
  let shCmds = genShellCmds(cmds)

  # we use two temporary variables. One to store total output of all commands
  # and the other to store the last exitCode.
  let exCodeSym = genSym(nskVar, "exitCode")
  let outputSym = genSym(nskVar, "outputStr")
  let outerrSym = genSym(nskVar, "outerrStr")
  result.add quote do:
    var `outputSym` = ""
    var `exCodeSym`: int
    var `outerrSym` = ""

  for cmd in shCmds:
    let qCmd = nilOrQuote(cmd)
    result.add quote do:
      # use the exit code to determine if next command should be run
      if `exCodeSym` == 0:
        let tmp = execShell(`qCmd`, `debugConfig`, `options`)
        `outputSym` = `outputSym` & tmp[0]
        `outerrSym` = tmp[1]
        `exCodeSym` = tmp[2]
      else:
        if dokRuntime in `debugConfig`:
          echo "Skipped command `" &
            `qCmd` &
            "` due to failure in previous command!"

  var resBody: NimNode = newStmtList()
  resBody.add result
  if combineOutAndErr:
    # possibly combine stdout & stderr by appending the latter and return 2 tuple
    resBody.add quote do:
      ## TODO: this should not be necessary if we hand `poStdErrToStdOut` no?
      `outputSym` = `outputSym` & `outerrSym`
      (`outputSym`, `exCodeSym`)
  else:
    # define the tuple 3 tuple we return in case we keep error
    resBody.add quote do:
      (`outputSym`, `outerrSym`, `exCodeSym`)
  result = quote do:
    block:
      `resBody`

  when defined(debugShell):
    echo result.repr

template parseTmpl(procName, enumType, name: untyped): untyped =
  proc `procName`(n: NimNode): NimNode =
    case n.kind
    of nnkIdent, nnkSym: result = n
    of nnkCurly:
      for ch in n:
        # check if this can be parsed as `DebugOutputKind`
        case ch.kind
        of nnkIdent:
          discard parseEnum[enumType](ch.strVal)
        of nnkCall:
          doAssert ch[0].strVal == astToStr(enumType)
        of nnkSym:
          # we trust that this is a valid symbol for an enum field
          discard
        else:
          error("Argument to `" & $name & "` in curly must be an identifier corresponding " &
            "to a field of `" & astToStr(enumType) & "`! Argument is: " &
            $(ch.repr) & " of kind " & $(ch.kind))
      result = n
    else:
      error("Invalid node kind for `" & $name & "`: " & $n.kind & "!")

parseTmpl(parseDebugConfig, DebugOutputKind, "debug")
parseTmpl(parseProcessOptions, ProcessOption, "options")

proc parseCombineAndErr(n: NimNode): bool =
  case n.kind
  of nnkIdent, nnkSym: result = parseBool(n.strVal)
  else:
    error("Invalid argument to `combineOutAndErr` in `shellVerbose`! Requires a " &
      "bool literal!")

proc parseShellVerboseArgs(combineOutAndErrDefault: bool,
                           args: NimNode): (NimNode, NimNode, bool, NimNode) =
  var
    cmds: NimNode
    cfgArg: NimNode
    optArg: NimNode
    combineOutAndErr: bool = combineOutAndErrDefault # default is true
  expectKind(args, nnkArglist)
  expectKind(args[args.len - 1], nnkStmtList)
  var idx = 0
  for arg in args:
    case arg.kind
    of nnkExprEqExpr:
      let argStr = arg[0].strVal
      case argStr
      of "debug", "debugConfig":
        cfgArg = parseDebugConfig(arg[1])
      of "options", "processOptions":
        optArg = parseProcessOptions(arg[1])
      of "combineOutAndErr":
        combineOutAndErr = parseCombineAndErr(arg[1])
    of nnkCurly:
      if idx == 0:
        cfgArg = parseDebugConfig(arg)
      elif idx == 1:
        optArg = parseProcessOptions(arg)
      else:
        error("Invalid unnamed argument at index " & $idx & "!")
    of nnkStmtList, nnkIdent:
      cmds = arg
    else:
      error("Invalid node kind encountered while parsing args of `shellVerbose`! " &
        "Node is " & $(arg.repr) & " of kind " & $(arg.kind))
    inc idx
  if cfgArg.isNil:
    cfgArg = newLit defaultDebugConfig
  if optArg.isNil:
    if combineOutAndErrDefault:
      optArg = newLit defaultProcessOptions
    else:
      optArg = newLit defaultProcessOptionsErr
  result = (cfgArg, optArg, combineOutAndErr, cmds)

macro shellVerbose*(args: varargs[untyped]): untyped =
  ## See the `shell` macro below for a general explanation.
  ##
  ## This macro differs from `shell` in as such that it
  ## 1. returns a tuple of
  ##   - `output: string` <- output of the shell command to stdout
  ##   - `exitCode: int` <- the exit code as an integer
  ## 2. allows to customize the error output behavior by handing the
  ## argument `debugConfig` (see below) as well as the process options
  ## with which `startProcess` is called by using the `options` argument.
  ##
  ## As you notice the macro signature is `args: varargs[untyped]`. This
  ## macro parses the given arguments manually (to allow multiple named arguments
  ## in an untyped macro). If the arguments are not named, they are expected
  ## in the order as shown below. `combineOutAndErr` has to be named!
  ##
  ## The following arguments are possible:
  ## - `debug`, `debugConfig`: a set of `DebugOutputKind`
  ## - `options`, `processOptions`: a set of `ProcessOption` (see `stdlib.osproc`)
  ## - `combineOutAndErr`: a static bool to decide if the macro should return a
  ##   2 tuple of `(output: string, errCode: int)` (`stderr` is appended to `stdout`)
  ##   or a 3 tuple of `(output, outerr: string, errCode: int)` (`stderr` separate)
  ##   The latter can also be had by using the `shellVerboseErr` overload below.
  runnableExamples:
    let (res, code) = shellVerbose(debug = {dokCommand}, options = {poEvalCommand},
                                   combineOutAndErr = true):
      echo "test"

    assert res == "test"
    assert code == 0

  let (cfgArg, optArg, combineOutAndErr, cmds) = parseShellVerboseArgs(
    combineOutAndErrDefault = true,
    args
  )
  result = shellVerboseImpl(cfgArg, optArg, combineOutAndErr = combineOutAndErr, cmds)

macro shellVerboseErr*(args: varargs[untyped]): untyped =
  ## Run shell command, return `(stdout, stderr, code)`. This is an overload
  ## of `shellVerbose` with `combineOutAndErr = false` by default.
  runnableExamples:
    let (res, err, code) = shellVerboseErr {dokCommand}:
      echo "test"

    assert res == "test"
    assert code == 0

  let (cfgArg, optArg, combineOutAndErr, cmds) = parseShellVerboseArgs(
    combineOutAndErrDefault = false,
    args
  )
  result = shellVerboseImpl(cfgArg, optArg, combineOutAndErr = combineOutAndErr, cmds)

macro shell*(cmds: untyped): untyped =
  ## A mini DSL to write shell commands in Nim. Some constructs are not
  ## implemented. If in doubt, put (parts of) the command into `" "`.
  ##
  ## The command is echoed before it is run. It is prefixed by
  ## ```
  ## shellCmd:
  ## ```
  ## If there is output, the output is echoed. Each successive line of the
  ## output is prefixed by
  ## ```
  ## shell>
  ## ```
  ##
  ## If multiple commands are run in succession (i.e. multiple statements in
  ## the macro body) and one command returns a non-zero exit code, the following
  ## commands will not be run. Instead a warning message will be shown.
  ##
  ## For usage with NimScript the output can only be echoed after the
  ## call has finished.
  ##
  ## The exit code of the command is dropped. If you wish to inspect
  ## the exit code, use `shellVerbose` above.
  result = quote do:
    discard shellVerbose(debug = defaultDebugConfig, options = defaultProcessOptions):
      `cmds`

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

  let qCmd = nilOrQuote(shCmd)
  result = quote do:
    `nimSym` = asgnShell(`qCmd`)[0]

  when defined(debugShell):
    echo result.repr
