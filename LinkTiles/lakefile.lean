import Lake

open Lake DSL

package linkTiles

require oria from "../oria"

@[default_target]
lean_lib LinkTiles

lean_lib LinkTilesTests

lean_exe «link-tiles» where
  root := `Main
  supportInterpreter := true
lean_exe «link-tiles-test» where
  root := `tests.Artifact
  supportInterpreter := true
