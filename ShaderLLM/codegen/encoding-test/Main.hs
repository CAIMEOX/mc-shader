module Main (main) where

import Control.Exception (bracket_)
import Control.Monad (forM_, unless)
import Data.ByteString qualified as B
import Data.Text.Encoding qualified as T
import GHC.IO.Encoding (getLocaleEncoding, mkTextEncoding, setLocaleEncoding)
import Qwen.Datapack (compileDatapack)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "qwen-encoding" $ \root -> do
  previous <- getLocaleEncoding
  gbk <- mkTextEncoding "CP936"
  bracket_ (setLocaleEncoding gbk) (setLocaleEncoding previous) (compileDatapack root)
  paths <- files root
  forM_ paths $ \path -> do
    bytes <- B.readFile path
    _ <- either (fail . ((path ++ ": ") ++) . show) pure (T.decodeUtf8' bytes)
    unless (not (B.elem 13 bytes)) (fail (path ++ ": expected LF line endings"))
  putStrLn "Generated data pack is UTF-8 with LF under a GBK locale."
  where
    files root = do
      names <- listDirectory root
      fmap concat $ mapM (visit . (root </>)) names
    visit path = do
      directory <- doesDirectoryExist path
      if directory then files path else pure [path]
