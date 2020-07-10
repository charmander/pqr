import json
import os
import posix
import streams


const PACKAGE_JSON = "package.json"


proc showUsage() =
  stderr.writeLine("Usage: pqr <command> [<args>...]")


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


proc getScript(scriptName: string): ScriptResult =
  ## Gets the named script from the nearest package.json, changing the working directory to the one containing that package.json, or to the root if a package.json wasn’t found.

  var packageInfoStream: FileStream

  while true:
    try:
      packageInfoStream = streams.openFileStream(PACKAGE_JSON)
      break
    except IOError:
      let error = os.osLastError()

      if error == OSErrorCode(posix.ENOENT):
        if os.sameFile(".", ".."):
          return ScriptResult(kind: noPackageInfo)

        os.setCurrentDir(os.ParDir)
        continue

      raise os.newOSError(error)

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

let initialDir = os.getCurrentDir()
let scriptName = argv[0]
let scriptResult = getScript(scriptName)

case scriptResult.kind
of noPackageInfo:
  stderr.writeLine("error: no ", PACKAGE_JSON, " found at any level above ", initialDir)
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
