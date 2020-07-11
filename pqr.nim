import json
import os
import posix
import streams


when defined(linux):
  var O_SEARCH_OR_O_PATH {.importc: "O_PATH", header: "<fcntl.h>".}: cint
else:
  var O_SEARCH_OR_O_PATH {.importc: "O_SEARCH", header: "<fcntl.h>".}: cint

var O_DIRECTORY {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint
var AT_FDCWD {.importc: "AT_FDCWD", header: "<fcntl.h>".}: cint
proc openat(fd: cint, path: cstring, oflag: cint): cint {.varargs, importc, header: "<fcntl.h>", sideEffect.}
proc fstatat(
  fd: cint,
  path: cstring,  # XXX: restrict necessary, even with header?
  buf: var Stat,
  flag: cint,
): cint {.importc, header: "<sys/stat.h>", sideEffect.}


const PACKAGE_JSON = "package.json"


proc showUsage() =
  stderr.writeLine("Usage: pqr <command> [<args>...]")


type
  PackageFds {.requiresInit.} = object
    packageInfo: cint
    packageRoot: cint


type
  ScriptResultKind {.pure.} = enum
    noPackageInfo   ## There was no package.json in the working directory or any of its ancestors.
    scriptNotFound  ## The named script didn’t exist in the nearest package.json.
    script
  ScriptResult {.requiresInit.} = object
    case kind: ScriptResultKind
    of noPackageInfo: discard
    of scriptNotFound:
      notFoundPackageRoot: string  ## The directory containing the package.json file that was used.
    of script:
      packageRoot: string
      script: string


proc closeFd(fd: cint) {.raises: [OSError].} =
  if posix.close(fd) != 0:
    raise os.newOSError(os.osLastError())


proc getPackageFds(initialDir: cint): PackageFds {.raises: [OSError].} =
  var dir = initialDir
  var fd = openat(dir, PACKAGE_JSON, posix.O_RDONLY)
  var dirInfo: tuple[dev: posix.Dev, ino: posix.Ino]

  while true:
    if fd != -1:
      return PackageFds(packageInfo: fd, packageRoot: dir)

    let error = os.osLastError()

    if error != OSErrorCode(posix.ENOENT):
      raise os.newOSError(error)

    if dir == initialDir:
      var stat: posix.Stat

      if fstatat(dir, $os.CurDir, stat, 0) != 0:
        raise os.newOSError(os.osLastError())

      dirInfo = (dev: stat.st_dev, ino: stat.st_ino)

    let parent = openat(dir, os.ParDir, O_SEARCH_OR_O_PATH or O_DIRECTORY)

    if parent == -1:
      raise os.newOSError(os.osLastError())

    if dir != initialDir:
      closeFd(dir)

    let parentInfo =
      block:
        var stat: posix.Stat

        if posix.fstat(parent, stat) != 0:
          raise os.newOSError(os.osLastError())

        (dev: stat.st_dev, ino: stat.st_ino)

    if parentInfo == dirInfo:
      closeFd(parent)
      return PackageFds(packageInfo: -1, packageRoot: -1)

    dir = parent
    dirInfo = parentInfo
    fd = openat(dir, PACKAGE_JSON, posix.O_RDONLY)


proc getScript(scriptName: string): ScriptResult =
  ## Gets the named script from the nearest package.json, and makes its parent the working directory if successful.

  let packageFds = getPackageFds(AT_FDCWD)

  if packageFds.packageInfo == -1:
    return ScriptResult(kind: noPackageInfo)

  let packageInfoStream = block:
    var packageInfoFile: File

    if not packageInfoFile.open(packageFds.packageInfo):
      raise newException(IOError, "couldn’t open package.json descriptor as File")

    streams.newFileStream(packageInfoFile)

  if packageFds.packageRoot != AT_FDCWD:
    if posix.fchdir(packageFds.packageRoot) != 0:
      raise os.newOSError(os.osLastError())

    closeFd(packageFds.packageRoot)

  let packageRoot = os.getCurrentDir()
  let packageInfo = parseJson(packageInfoStream, filename = packageRoot / PACKAGE_JSON)
  let scripts = packageInfo{"scripts"}

  if scripts != nil and (let script = scripts{scriptName}; script != nil) and script.kind == JString:
    ScriptResult(kind: ScriptResultKind.script, packageRoot: packageRoot, script: script.getStr())
  else:
    ScriptResult(kind: scriptNotFound, notFoundPackageRoot: packageRoot)


let argv = os.commandLineParams()

if argv.len == 0:
  showUsage()
  quit(QuitFailure)

let scriptName = argv[0]
let scriptResult = getScript(scriptName)

case scriptResult.kind
of noPackageInfo:
  stderr.writeLine("error: no ", PACKAGE_JSON, " found at any level above ", os.getCurrentDir())
of scriptNotFound:
  stderr.writeLine("error: no script named ", scriptName, " in ", scriptResult.notFoundPackageRoot / PACKAGE_JSON)
of script:
  # : is impossible to escape in $PATH
  if ':' notin scriptResult.packageRoot:
    let packageBin = scriptResult.packageRoot / "node_modules" / ".bin"
    let inheritedPath = os.getEnv("PATH")
    let extendedPath =
      if inheritedPath == "":
        packageBin
      else:
        packageBin & ":" & inheritedPath

    os.putEnv("PATH", extendedPath)

  if '\0' in scriptResult.script:
    stderr.writeLine("error: script contains a NUL character")
    quit(QuitFailure)

  let execArgs = @["sh", "-c", "--", scriptResult.script & " \"$@\"", "sh"] & argv[1..^1]
  let cexecArgs = allocCStringArray(execArgs)
  discard posix.execv("/bin/sh", cexecArgs)
  raise os.newOSError(os.osLastError())

quit(QuitFailure)
