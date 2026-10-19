module Manifold.Messages (Message (..), chat, actionbar, chapter, victory, resources) where

import Manifold.Json

data Message
  = StageUnavailable
  | PutDown
  | TurnSpace
  | CubeControls
  | ExitHelp
  | RingsName
  | RingsVictory
  | RingsEnding
  | RingsBlueHelp
  | RingsRelayHelp
  | RingsGoalHelp
  | AtriumControls
  | AtriumExplore
  | JoineryName
  | JoineryControls
  | JoineryRoute
  | JoineryRecovery
  | JoineryBlocked
  | JoineryStand
  | JoineryTool
  | JoineryVictory
  | JoineryEnding
  | FlightControls
  deriving (Eq, Show, Enum, Bounded)

-- The component and both resource catalogs share one message identity.
entry :: Message -> (String, String, String, [Json])
entry message = case message of
  StageUnavailable -> ("stage.unavailable", "Reopen the world to load the Manifold stage.", "重新进入世界以加载 Manifold 场景。", [])
  PutDown -> ("action.put_down", "Put the cube down first.", "先放下方块。", [])
  TurnSpace -> ("action.turn_space", "Step away before turning.", "退开一点再转向。", [])
  CubeControls -> ("help.cube_controls", "%s picks up or places a cube. While grounded and empty-handed, look in a direction and press %s to turn gravity.", "%s 取放方块；站稳、空手时，朝目标方向按 %s 切换重力。", [keybind "key.use", keybind "key.sprint"])
  ExitHelp -> ("help.exit", "%s exits the scene.", "%s 离开场景。", [literal "/function manifold:stop"])
  RingsName -> ("rings.name", "Three Rings", "三环庭", [])
  RingsVictory -> ("rings.victory", "Rings United", "三环归庭", [])
  RingsEnding -> ("rings.ending", "Borrowed ground, shared garden.", "借来的地面，终于成为共同的花园", [])
  RingsBlueHelp -> ("rings.help.blue", "Find the blue cube behind the entrance platform. Place it in the temporary blue socket, then land on its frozen side to reach the gallery.", "蓝块在入口平台背面。把它送到蓝色临时槽，再借冻结的侧面进入侧廊。", [])
  RingsRelayHelp -> ("rings.help.relay", "Send the amber cube through the periodic shaft to open the green court. The green cube can take over the blue cube's power supply.", "琥珀块沿投递井越过边界，接通绿色内庭。绿块可以接替蓝块供能。", [])
  RingsGoalHelp -> ("rings.help.goal", "Place all three cubes in their main sockets. %s restores your checkpoint.", "将三枚方块分别送入主座；%s 返回检查点。", [literal "/function manifold:three_rings/checkpoint/restore"])
  AtriumControls -> ("atrium.help.controls", "While grounded, look in a direction and press %s to turn gravity. %s jumps.", "站稳后，朝目标方向按 %s 切换重力；%s 跳跃。", [keybind "key.sprint", keybind "key.jump"])
  AtriumExplore -> ("atrium.help.explore", "Walk the repeating lattice and explore each of its six gravity directions.", "沿无限重复的网格行走，探索六个方向的重力。", [])
  JoineryName -> ("joinery.name", "Joinery Court", "榫庭", [])
  JoineryControls -> ("joinery.help.controls", "Hold the Joinery Tool, aim at any timber and press %s. It moves four blocks along gravity. %s turns gravity while grounded.", "手持榫尺，瞄准任意木梁按 %s，沿当前重力平移四格；站稳后按 %s 切换重力。", [keybind "key.use", keybind "key.sprint"])
  JoineryRoute -> ("joinery.help.route", "Return all six colored, numbered timbers to their home positions. Every visible copy shares the same position; the tool reaches 96 blocks.", "将六根带颜色与编号的木梁移回归位点。重复空间中的同一木梁共享位置；榫尺可触及 96 格。", [])
  JoineryRecovery -> ("joinery.help.recovery", "%s restores the previous move and standing position. %s returns to the latest checkpoint.", "%s 撤销上一步并恢复站位；%s 返回最近检查点。", [literal "/function manifold:joinery/undo", literal "/function manifold:joinery/checkpoint/restore"])
  JoineryBlocked -> ("joinery.action.blocked", "Another timber holds this joint.", "榫口仍被另一根木梁扣住。", [])
  JoineryStand -> ("joinery.action.stand", "Stand clear on a stationary timber.", "请站到滑动范围外的另一根木梁上。", [])
  JoineryTool -> ("joinery.tool", "Joinery Tool", "榫尺", [])
  JoineryVictory -> ("joinery.victory", "Joined as One", "六榫归一", [])
  JoineryEnding -> ("joinery.ending", "One joint. Endless timber.", "一榫合拢，万木相连。", [])
  FlightControls -> ("flight.help.controls", "Move with your movement keys. %s / %s: rise / descend. %s: turn gravity. %s + %s: toggle flight.", "使用移动按键飞行；%s / %s 上升与下降；%s 切换重力；同时按 %s + %s 切换飞行。", [keybind "key.jump", keybind "key.sneak", keybind "key.sprint", keybind "key.jump", keybind "key.sneak"])
  where
    keybind name = object [("keybind", string name)]
    literal value = object [("text", string value)]

key :: Message -> String
key message = let (suffix, _, _, _) = entry message in "manifold." ++ suffix

component :: String -> Message -> String
component color message =
  let (_, english, _, arguments) = entry message
   in render (object ([("translate", string (key message)), ("fallback", string english), ("color", string color)] ++ [("with", array arguments) | not (null arguments)]))

chat, actionbar :: String -> Message -> String
chat color message = "tellraw @s " ++ component color message
actionbar color message = "title @s actionbar " ++ component color message

chapter :: Message -> [String]
chapter message = ["title @s reset", "title @s actionbar {text:\"\"}", "title @s times 10 35 15", "title @s title " ++ component (if message == JoineryName then "#d6cbb8" else "aqua") message]

victory :: Message -> Message -> [String]
victory heading ending = ["title @s reset", "title @s actionbar {text:\"\"}", "title @s times 10 60 20", "title @s subtitle " ++ component "white" ending, "title @s title " ++ component "gold" heading]

resources :: [(FilePath, String)]
resources =
  [ ( "assets/manifold/lang/" ++ language ++ ".json",
      render (object [(key message, string (select (entry message))) | message <- [minBound .. maxBound]])
    )
  | (language, select) <- [("en_us", \(_, english, _, _) -> english), ("zh_cn", \(_, _, chinese, _) -> chinese)]
  ]
