module

public import LinkTiles
public import Oria.Meta.Datapack
import Lean.Util.Path

namespace LinkTiles

/-- Native build entry point, using Oria's standard compiler and environment registry. -/
public def compile (moduleName : Lean.Name) (spec : Oria.Datapack.Spec) : IO Oria.Datapack.Artifact := do
  Lean.initSearchPath (← Lean.findSysroot)
  unsafe Lean.enableInitializersExecution
  let env ← Lean.importModules #[{module := moduleName}] {} (loadExts := true)
  IO.ofExcept ((Oria.Datapack.compile env spec).mapError reprStr)

/-- Export the compiled functions and the native interaction event resource together. -/
public def write (artifact : Oria.Datapack.Artifact) (directory : System.FilePath) : IO Unit := do
  artifact.writeTo directory
  let folder := directory / "data" / "link_tiles" / "advancement"
  IO.FS.createDirAll folder
  IO.FS.writeFile (folder / "click.json") (Input.advancement.pretty 100 ++ "\n")

end LinkTiles
