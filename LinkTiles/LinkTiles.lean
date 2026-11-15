module

public import LinkTiles.Game
meta import Oria
meta import Oria.Datapack
meta import LinkTiles.Game

set_option maxHeartbeats 8000000

namespace LinkTiles

open Oria

public def game : Datapack.Spec := Datapack.build {
    ns := "link_tiles", description := "LinkTiles: a typed 10 by 10 linking puzzle" } do
  Datapack.global state
  View.register
  Datapack.onLoad Game.setup.ref
  Datapack.onTick Game.tick.ref
  Datapack.entry "new" Game.newGame.ref
  Datapack.entry "hint" Game.hint.ref
  Datapack.entry "reshuffle" Game.reshuffle.ref
  Datapack.entry "replay" Game.replay.ref
  Datapack.entry "release" Game.release.ref

end LinkTiles
