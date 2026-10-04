module Main (main) where

import Control.Monad (forM_, unless)
import Data.Bits qualified as Bits
import Data.Char (ord)
import Data.Either (isLeft)
import Data.List (nub)
import Signal.Frame qualified as Frame
import Signal.Protocol
import Signal.Rotate qualified as Rotate
import Signal.Stream qualified as Stream
import Signal.Water qualified as Water

main :: IO ()
main = do
  forM_
    [ Request i m p
    | i <- [1, 255, 256, 32768, 65535],
      m <- [minBound .. maxBound],
      p <- [0, 1, 16, 63]
    ]
    $ \request -> do
      unless ((encode request >>= decode) == Right request) (fail "Request round trip")
      unless (resultBit request `elem` [0, 1]) (fail "Binary GPU result")
      unless (resultSymbol request `elem` [0 .. 3]) (fail "GPU symbol range")
  unless (all (isLeft . encode) [Request 0 Light 1, Request 65536 Light 1, Request 1 Heavy 64]) (fail "Request ranges")
  unless (isLeft (decode 0xff0000)) (fail "Zero sequence is invalid")
  let bits = [resultBit (Request i Compute 1) | i <- [100 .. 131]]
  unless (sum bits >= 8 && sum bits <= 24) (fail "Payload exercises both result branches")
  forM_ [1000, 5000, 60000] $ \start -> do
    payload <- either fail pure (balancedPayload start)
    unless (length payload == 32 && sum (map resultBit payload) == 16) (fail "Balanced payload")
    unless (length (nub (map sequenceId payload)) == 32) (fail "Unique payload sequences")
    unless (all (\request -> sequenceId request >= start && sequenceId request <= 65535) payload) (fail "Payload sequence bounds")
    four <- either fail pure (balancedFourPayload start)
    unless (all (\symbol -> length (filter ((== symbol) . resultSymbol) four) == 8) [0 .. 3]) (fail "Balanced four-symbol payload")
    unless (length (nub (map sequenceId four)) == 32) (fail "Unique four-symbol sequences")
  unless (isLeft (balancedPayload 65535)) (fail "Payload requires enough sequences")
  unless (Water.meanGap [50, 100, 150, 200] == Just 50000) (fail "Position event interval")
  unless (Water.meanGap [1050, 1100, 1150, 1200] == Water.meanGap [50, 100, 150, 200]) (fail "Time origin invariance")
  unless (Water.meanGap [50, 100] == Nothing) (fail "Receiver requires enough events")
  unless (Water.clusterMedian [95, 99, 195, 290, 385, 390] == Just 95000) (fail "Burst merging")
  unless (Water.clusterMedian [0, 50, 150, 200] == Just 50000) (fail "Median tolerates an isolated delayed event")
  unless (Water.clusterMedian [0, 5, 10, 50] == Nothing) (fail "Three complete groups required")
  unless (Water.clusterMedian [1095, 1099, 1195, 1290, 1385, 1390] == Water.clusterMedian [95, 99, 195, 290, 385, 390]) (fail "Burst feature time origin invariance")
  model <- maybe (fail "Timing calibration") pure (Water.fitModel [50000, 51000] [95000, 97000])
  unless (map (Water.receive model) [49000, 96000] == [0, 1]) (fail "Live timing receiver")
  inverse <- maybe (fail "Inverse timing calibration") pure (Water.fitModel [96000] [50000])
  unless (map (Water.receive inverse) [49000, 96000] == [1, 0]) (fail "Receiver polarity")
  unless (Water.fitModel [50000] [51000] == Nothing) (fail "Receiver separation")
  (_, cuts) <- maybe (fail "Four-level calibration") pure (Water.fitFour [[50000, 51000], [74000, 76000], [120000], [190000]])
  unless (map (Water.receiveFour cuts) [50000, 75000, 120000, 190000] == map Just [0, 1, 3, 2]) (fail "Gray-mapped four-level receiver")
  unless (Water.fitFour [[50000], [50000], [120000], [190000]] == Nothing) (fail "Four-level separation")
  unless (Water.receiveFour [70000, 60000, 90000] 50000 == Nothing) (fail "Ordered four-level cuts")
  forM_ [-179000000, -90000000, -20000, 20000, 90000000, 179000000] $ \yaw -> do
    turn <- maybe (fail "Probe direction") pure (Rotate.probeTurn yaw)
    let marker = yaw + turn * 1000000
        wrapped = (marker + 180000000) `mod` 360000000 - 180000000
    unless (Rotate.isMarker marker && marker `rem` 360000000 == marker && wrapped == yaw) (fail "Probe survives tick remainder and clears on packet wrapping")
  unless (Rotate.probeTurn 0 == Nothing && Rotate.probeTurn 5000 == Nothing) (fail "Probe rounding guard")
  unless (Rotate.responseMean [10, 20, 30] == Just 20000 && Rotate.responseMean [10, 20] == Nothing) (fail "Response latency feature")
  unless (Frame.crc8 (map (fromIntegral . ord) "123456789") == 0xf4) (fail "CRC-8 check vector")
  forM_ ["h", "hi from shader", "quote: \" and slash: \\", replicate 64 'x'] $ \message -> do
    frame <- either fail pure (Frame.encodeFrame message)
    unless (Frame.decodeFrame frame == Right message) (fail "Message frame round trip")
    unless (length (Frame.frameBits frame) == 8 * (length message + 2)) (fail "Frame bit count")
    forM_ [(byteIndex, bitIndex) | byteIndex <- [0 .. length frame - 1], bitIndex <- [0 .. 7]] $ \(byteIndex, bitIndex) -> do
      let corrupted = [if i == byteIndex then Bits.complementBit byte bitIndex else byte | (i, byte) <- zip [0 ..] frame]
      unless (isLeft (Frame.decodeFrame corrupted)) (fail "Single-bit corruption detected")
  unless (all (isLeft . Frame.encodeFrame) ["", "line\nbreak", replicate 65 'x']) (fail "Message alphabet and bounds")
  unless (isLeft (Frame.decodeFrame [0, 0])) (fail "Idle zero stream is not a message")
  unless (all (== 0) (Stream.payloadBits 1000 Stream.Zeroes) && all (== 1) (Stream.payloadBits 1000 Stream.Ones)) (fail "Stream constant patterns")
  unless (Stream.payloadBits 1000 Stream.Alternating == take Stream.payloadLength (cycle [0, 1])) (fail "Stream alternating pattern")
  let randomBits = Stream.payloadBits 1000 Stream.DigestBits
  unless (length randomBits == 64 && sum randomBits >= 16 && sum randomBits <= 48) (fail "Stream digest bit balance")
  unless
    ( map (Stream.classifyGap 16 32) [1, 3, 12, 15, 16, 20, 32, 40]
        == [ Stream.Burst,
             Stream.Burst,
             Stream.Bit 0,
             Stream.Bit 0,
             Stream.Bit 1,
             Stream.Bit 1,
             Stream.Delimiter,
             Stream.Delimiter
           ]
    )
    (fail "Stream tick gap classification")
  putStrLn "Protocol, rotation and free-fall receivers, message framing and CRC semantics passed."
