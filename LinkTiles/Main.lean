module

import LinkTiles.Export

public def main (args : List String) : IO Unit := do
  match args with
  | [directory] => LinkTiles.write (← LinkTiles.compile `LinkTiles LinkTiles.game) directory
  | _ => throw (.userError "usage: lake exe link-tiles <empty-directory>")
