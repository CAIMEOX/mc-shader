module Qwen.TextIO (readUtf8, writeUtf8) where

import Data.ByteString qualified as B
import Data.Text qualified as T
import Data.Text.Encoding qualified as T

readUtf8 :: FilePath -> IO String
readUtf8 path = do
  bytes <- B.readFile path
  either (fail . ((path ++ ": ") ++) . show) (pure . T.unpack) (T.decodeUtf8' bytes)

-- Binary writes preserve the LF characters supplied by the resource generators.
writeUtf8 :: FilePath -> String -> IO ()
writeUtf8 path = B.writeFile path . T.encodeUtf8 . T.pack
