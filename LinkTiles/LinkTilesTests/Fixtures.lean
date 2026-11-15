module

public import LinkTiles
meta import Oria
meta import Oria.Datapack
meta import LinkTiles

set_option maxHeartbeats 8000000

namespace LinkTilesTests

open Oria LinkTiles

@[mcfunction]
private def seeded := show Prog _ Unit from do
  Game.newGame.call
  Deal.begin.call 42

@[mcfunction]
private def query := show Prog _ Unit from do
  let a ← Oria.Std.Scoreboard.get (.named "#test") "link.a"
  let b ← Oria.Std.Scoreboard.get (.named "#test") "link.b"
  let ok ← Geometry.route.call a b
  if ok then Oria.Std.Scoreboard.set (.named "#test") "link.ok" 1
  else Oria.Std.Scoreboard.set (.named "#test") "link.ok" 0

@[mcfunction]
private def erasePair := show Prog _ Unit from do
  let a ← Oria.Std.Scoreboard.get (.named "#test") "link.a"
  let b ← Oria.Std.Scoreboard.get (.named "#test") "link.b"
  Index.erase.call a
  Index.erase.call b

public def specimen : Datapack.Spec := {
  game with registrations := (game.registrations.filter fun
    | .hook .tick .. => false
    | _ => true) ++ #[.entry "seeded" seeded.ref, .entry "tick" Game.tick.ref,
      .entry "rebuild" Index.reset.ref,
      .entry "query" query.ref, .entry "index-step" Index.step.ref,
      .entry "erase-pair" erasePair.ref] }

end LinkTilesTests
