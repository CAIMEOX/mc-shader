module Flame.Program (makePipeline) where

import Flame.Domain
import Flame.Pipeline
import Flame.Protocol (packetDimensions)

data State = State {thermalState :: String, gasState :: String, velocityState :: String}

state :: String -> State
state suffix = State ("thermal_" ++ suffix) ("gas_" ++ suffix) ("velocity_" ++ suffix)

data Execution = SimulationSlot Int | SingleStepCommit | SnapshotChange

gated :: Execution -> Pass -> Pass
gated execution p =
  (parameterized values p)
    { passVertex = "flame:post/step",
      passInputs = if any ((== "Control") . inputName) (passInputs p) then passInputs p else Color "Control" (Target "control_a") : passInputs p
    }
  where
    values = case execution of
      SimulationSlot n -> [fromIntegral n, 0, 0, 0]
      SingleStepCommit -> [0, 1, 0, 0]
      SnapshotChange -> [0, 2, 0, 0]

makePipeline :: Config -> Pipeline
makePipeline c = Pipeline targets ordered
  where
    t = Target
    cells = volume (grid c)
    extent n = Fixed 256 ((n * cells + 255) `div` 256)
    (pw, ph) = packetDimensions c
    packetExtent = Fixed pw ph
    (rw, rh) = renderSize c
    targets =
      [ TargetSpec (t "packet_next") packetExtent False,
        TargetSpec (t "packet") packetExtent True,
        TargetSpec (t "terrain") (Fixed 16 ((volume (region c) + 15) `div` 16)) True,
        TargetSpec (t "swap") Screen False
      ]
        ++ [TargetSpec (t n) (Fixed 8 1) True | n <- ["control_a", "control_b"]]
        ++ [TargetSpec (t n) (extent 1) True | n <- ["solid", "curl_work", "rhs", "pressure_a", "pressure_b", "render_field"]]
        ++ [TargetSpec (t n) (extent 3) True | n <- ["thermal_a", "thermal_b", "velocity_a", "velocity_b", "velocity_work"]]
        ++ [TargetSpec (t n) (extent 5) True | n <- ["gas_a", "gas_b", "gas_work"]]
        ++ [TargetSpec (t n) (Fixed rw rh) True | n <- ["guide", "volume"]]
        ++ [TargetSpec (t "bounds") (Fixed 16 ((volume (mapV3 (\n -> (n + 3) `div` 4) (grid c)) + 15) `div` 16)) True]
    common = [Color "Control" (t "control_a"), Color "Solid" (t "solid")]
    step slot old new =
      let p shader inputs output = gated (SimulationSlot slot) (pass shader (common ++ inputs) (t output))
          packet = Color "Packet" (t "packet")
          (pressure, pressureEnd) =
            pingPong
              (pressureIterations c)
              (\src dst -> p "pressure" [Color "Previous" src, Color "Rhs" (t "rhs")] (targetName dst))
              (t "pressure_a", t "pressure_b")
       in [ p "thermal" [packet, Color "Previous" (t (thermalState old)), Color "Gas" (t (gasState old))] (thermalState new),
            p "curl" [Color "Velocity" (t (velocityState old))] "curl_work",
            p "velocity" [Color "Previous" (t (velocityState old)), Color "Gas" (t (gasState old)), Color "Curl" (t "curl_work")] "velocity_work",
            p "divergence" [Color "Velocity" (t "velocity_work")] "rhs",
            p "pressure_init" [] "pressure_a"
          ]
            ++ pressure
            ++ [ p "project" [Color "Previous" (t "velocity_work"), Color "Pressure" pressureEnd] (velocityState new),
                 p "advect_gas" [Color "Previous" (t (gasState old)), Color "Velocity" (t (velocityState new))] "gas_work",
                 p "combustion" [packet, Color "Previous" (t "gas_work"), Color "Thermal" (t (thermalState new))] (gasState new)
               ]
    camera = [Color "Packet" (t "packet"), Color "Control" (t "control_a")]
    render shader inputs output = (pass shader (camera ++ inputs) (t output)) {passVertex = "flame:post/render"}
    ordered =
      [ pass "receive" [Color "Main" mainTarget, Color "Previous" (t "packet")] (t "packet_next"),
        pass "copy" [Color "In" (t "packet_next")] (t "packet"),
        pass "control" [Color "Packet" (t "packet"), Color "Previous" (t "control_b")] (t "control_a"),
        gated SnapshotChange (pass "decode" [Color "Packet" (t "packet")] (t "terrain")),
        gated SnapshotChange (pass "solid" [Color "Terrain" (t "terrain")] (t "solid"))
      ]
        ++ step 0 (state "b") (state "a")
        ++ step 1 (state "a") (state "b")
        ++ [gated SingleStepCommit (pass "copy" [Color "In" (t (name ++ "_a"))] (t (name ++ "_b"))) | name <- ["thermal", "gas", "velocity"]]
        ++ [ gated (SimulationSlot 0) (pass "render_field" [Color "Gas" (t "gas_b"), Color "Solid" (t "solid")] (t "render_field")),
             gated (SimulationSlot 0) (pass "bounds" [Color "Field" (t "render_field")] (t "bounds")),
             render "guide" [Depth "Depth" mainTarget] "guide",
             render "volume" [Depth "Depth" mainTarget, Color "Field" (t "render_field"), Color "Bounds" (t "bounds")] "volume",
             render "composite" [Color "Main" mainTarget, Depth "Depth" mainTarget, Color "Volume" (t "volume"), Color "Guide" (t "guide"), Color "Field" (t "render_field"), Color "Bounds" (t "bounds"), Color "Thermal" (t "thermal_b"), Color "Solid" (t "solid")] "swap",
             pass "copy" [Color "In" (t "control_a")] (t "control_b"),
             pass "copy" [Color "In" (t "swap")] mainTarget
           ]
