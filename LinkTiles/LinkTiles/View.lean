module

public import LinkTiles.Model
public import Oria.Std.Execute
meta import Oria
meta import LinkTiles.Model

set_option maxHeartbeats 2000000

namespace LinkTiles.View

open Oria Oria.Std Oria.Std.Command.Arg

private structure Label where
  text : String
  color : String
  deriving Nbt.Repr

private structure Row where
  text : String := "|"
  extra : Array Label := (Array.replicate 10 ⟨"    ", "dark_gray"⟩).push ⟨"|", "dark_gray"⟩
  deriving Nbt.Repr

private def colors : Array String := #["aqua", "gold", "green", "light_purple", "red"]
private def labels : Array Label := (Array.range 52).map fun i =>
  let n := i % 26
  let text := if n == 0 then "    " else (if n < 10 then "0" else "") ++ toString n ++ " "
  ⟨text, if i >= 26 then "white" else colors[n % 5]!⟩

private structure Ui where
  palette : Array Label := labels
  rows : Array Row := Array.replicate 10 {}
  deriving Nbt.Repr

private def ui : Nbt.Global Ui := Nbt.Global.init "ui" (.key "display") {}
public def register : Datapack.Builder Unit := Datapack.global ui

private def rowTarget (r : Nat) : Target := .selector (.allEntities {
  tags := [.include "link_tiles.row", .include s!"link_tiles.r{r}"], limit := some 1 })

public def entities : Target := .selector (.allEntities {tags := [.include "link_tiles.display"]})

private def spawnGrade : Grade := (Summon.grade (some (.relative 0 0 0))).handled

private def spawnCell (r c : Nat) : Prog spawnGrade Unit :=
  (Summon.at "minecraft:interaction"
    (.relative (.decimal (Float.ofNat c * 0.25 + 0.125)) (.decimal 0.04)
      (.decimal (Float.ofNat r * 0.25 + 0.125)))
    (some (.value (nbt% {width: 0.24f, height: 0.08f, response: true,
      Tags: ["link_tiles.display", "link_tiles.cell", $(s!"link_tiles.r{r}"), $(s!"link_tiles.c{c}")]})))).ignore

private def spawnText (r : Nat) : Prog spawnGrade Unit :=
  (Summon.at "minecraft:text_display"
    (.relative (.decimal 1.25) (.decimal 0.135) (.decimal (Float.ofNat r * 0.25 + 0.20)))
    (some (.value (nbt% {
      Tags: ["link_tiles.display", "link_tiles.row", $(s!"link_tiles.r{r}")],
      text: {text: "Preparing LinkTiles...", color: "aqua"},
      billboard: "fixed", line_width: 400, background: -16777216,
      shadow: true, see_through: false,
      transformation: {translation: [0f, 0f, 0f],
        left_rotation: [-0.70710677f, 0f, 0f, 0.70710677f],
        scale: [0.625f, 0.625f, 0.625f], right_rotation: [0f, 0f, 0f, 1f]}
    })))).ignore

private def spawnCells : Nat → Prog spawnGrade Unit
  | 0 => (Prog.pure Val.unit).weaken
  | n + 1 => do
    spawnCells n
    spawnCell (n / 10) (n % 10)

private def spawnRows : Nat → Prog spawnGrade Unit
  | 0 => (Prog.pure Val.unit).weaken
  | n + 1 => do
    spawnRows n
    spawnText n

private def beamTarget (n : Nat) : Target := .selector (.allEntities {
  tags := [.include "link_tiles.display", .include s!"link_tiles.beam{n}"], limit := some 1 })

private def spawnBeam (n : Nat) : Prog spawnGrade Unit :=
  (Summon.at "minecraft:block_display" (.relative 0 (.decimal 0.17) 0)
    (some (.value (nbt% {Tags: ["link_tiles.display", $(s!"link_tiles.beam{n}")],
      block_state: {id: "minecraft:gold_block"},
      transformation: {translation: [0f, 0f, 0f],
        left_rotation: [0f, 0f, 0f, 1f], scale: [0f, 0f, 0f], right_rotation: [0f, 0f, 0f, 1f]}})))).ignore

/-- Spawn one physical table in the caller's dimension, relative to the stored block origin. -/
@[mcfunction]
public def create := show Prog _ Unit from do
  (Kill.run entities).ignore
  let x ← state.origin[0]
  let y ← state.origin[1]
  let z ← state.origin[2]
  Execute.forEach [Execute.Step.positioned (.absolute (.dynamic x) (.dynamic y) (.dynamic z))] do
    spawnCells 100
    spawnRows 10
    spawnBeam 0
    spawnBeam 1
    spawnBeam 2

@[expose] public def renderGrade : Grade :=
  ⟨Req.dimension, Eff.memoryRead ||| Eff.memoryWrite ||| Eff.failure |||
    Eff.world ||| Eff.scoreboardRead ||| Eff.random⟩

/-- Host-specialized row selection keeps selector syntax static; only changed rows are sent. -/
private def renderRow (r : Nat) : Prog renderGrade Unit := do
  let selected ← state.selected
  let hintA ← state.hintA
  let hintB ← state.hintB
  let ticks ← state.routeTicks
  let rec cells (c : Val Int32) : Prog memory Unit := do
    if c >= 10 then return Val.unit
    let p := I32.lit (Int32.ofNat ((r + 1) * 12 + 1)) + c
    let color ← state.tiles[p]
    let label ← (show Prog .pure Int32 from do
      if color != 0 && (selected == p || (ticks > 0 && (hintA == p || hintB == p))) then
        return color + 26
      return color)
    (Nbt.copy ui ((Ui.Nbt.rows.at (I32.lit (Int32.ofNat r))).then Row.Nbt.extra |>.at c)
      ui (Ui.Nbt.palette.at label)).ignore
    cells (c + 1)
  cells 0
  (Nbt.store ui (Ui.Nbt.rows.at (I32.lit (Int32.ofNat r))) (.entity (rowTarget r)) (.key "text")).ignore

private def allRows : Nat → Prog renderGrade Unit
  | 0 => (Prog.pure Val.unit).weaken
  | n + 1 => do
    allRows n
    renderRow n

@[mcfunction]
public def render : Prog renderGrade Unit := allRows 10

/-- Refresh just the row containing a changed padded-grid cell. -/
@[mcfunction]
public def refresh (p : Val Int32) : Prog renderGrade Unit := do
  let row ← p / 12
  let rec choose : Nat → Prog renderGrade Unit
    | 0 => (Prog.pure Val.unit).weaken
    | n + 1 => do
      if row == I32.lit (Int32.ofNat (n + 1)) then renderRow n
      choose n
  choose 10

private def hide (n : Nat) :=
  (Data.modify (.entity (beamTarget n))
    ((Nbt.Path.key "transformation").field "scale") .set (.value (.nbt (nbt% [0f, 0f, 0f])))).ignore

@[mcfunction]
public def hideRoute := show Prog _ Unit from do
  hide 0
  hide 1
  hide 2

private def beam (n : Nat) (a b : Val Int32) := show Prog _ Unit from do
  let ar ← a / 12
  let br ← b / 12
  let ac := a - ar * 12
  let bc := b - br * 12
  let x ← (show Prog .pure Int32 from do if ac < bc then return ac else return bc)
  let z ← (show Prog .pure Int32 from do if ar < br then return ar else return br)
  let w ← (show Prog .pure Int32 from do if ac < bc then return bc - ac else return ac - bc)
  let h ← (show Prog .pure Int32 from do if ar < br then return br - ar else return ar - br)
  Execute.forEach [Execute.Step.storeResult (.nbt (.entity (beamTarget n))
      (((Nbt.Path.key "transformation").field "translation").at 0) .float (.decimal 0.03125))] do
    return (x - 1) * 8 + 4
  Execute.forEach [Execute.Step.storeResult (.nbt (.entity (beamTarget n))
      (((Nbt.Path.key "transformation").field "translation").at 2) .float (.decimal 0.03125))] do
    return (z - 1) * 8 + 4
  Execute.forEach [Execute.Step.storeResult (.nbt (.entity (beamTarget n))
      (((Nbt.Path.key "transformation").field "scale").at 0) .float (.decimal 0.03125))] do
    return w * 8 + 1
  Execute.forEach [Execute.Step.storeResult (.nbt (.entity (beamTarget n))
      (((Nbt.Path.key "transformation").field "scale").at 2) .float (.decimal 0.03125))] do
    return h * 8 + 1
  (Data.modify (.entity (beamTarget n))
    (((Nbt.Path.key "transformation").field "scale").at 1) .set (.value (.nbt (nbt% 0.015625f)))).ignore

/-- Three reusable display bars draw the exact route, including the outside ring. -/
@[mcfunction]
public def showRoute := show Prog _ Unit from do
  hideRoute.call
  let count ← Nbt.length state State.Nbt.route
  let a ← state.route[0]
  let b ← state.route[1]
  beam 0 a b
  if count > 2 then
    let c ← state.route[2]
    beam 1 b c
    if count > 3 then
      let d ← state.route[3]
      beam 2 c d

/-- Clickable, permission-free actions for the table owner. -/
@[mcfunction]
public def controls := (Tellraw.send .self (nbt% {text: "LinkTiles  ", color: "aqua", extra: [
  {text: "[New] ", click_event: {action: "run_command", command: "trigger link.action set 1"}},
  {text: "[Hint] ", click_event: {action: "run_command", command: "trigger link.action set 2"}},
  {text: "[Reshuffle] ", click_event: {action: "run_command", command: "trigger link.action set 3"}},
  {text: "[Replay] ", click_event: {action: "run_command", command: "trigger link.action set 4"}},
  {text: "[Release]", click_event: {action: "run_command", command: "trigger link.action set 5"}}
]})).ignore

end LinkTiles.View
