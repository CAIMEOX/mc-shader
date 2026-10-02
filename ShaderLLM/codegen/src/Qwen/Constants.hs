{-# LANGUAGE OverloadedStrings #-}

module Qwen.Constants (compileConstants) where

import Data.Aeson
import Data.Aeson.KeyMap qualified as K
import Data.ByteString.Lazy qualified as B
import Data.Char (ord)
import Data.Text qualified as T
import Qwen.GLSL qualified as G
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

compileConstants :: FilePath -> FilePath -> FilePath -> IO ()
compileConstants tokenizer chat output = do
  Object t <- either fail pure . eitherDecode =<< B.readFile (tokenizer </> "tokenizer-layout.json")
  Object c <- either fail pure . eitherDecode =<< B.readFile chat
  let get o k = case K.lookup k o of Just v -> v; Nothing -> error "Missing compiler field"
      parse v = case fromJSON v of Success a -> a; Error e -> error e
      bytes = parse (get t "byte_ids") :: [Int]
      prefix = map ord (T.unpack (parse (get c "prefix")))
      suffix = map ord (T.unpack (parse (get c "suffix")))
      u = case get t "unicode" of Object o -> o; _ -> error "Expected Unicode layout object"
      constant name value = G.constant G.Int name (G.int (parse value :: Int))
      array name xs = G.constantArray G.Int name (map G.int xs)
  createDirectoryIfMissing True output
  writeFile (output </> "tokenizer_constants.glsl") $
    G.renderUnit $
      G.TranslationUnit
        [ constant "MERGE_PROBES" (get t "merge_probe"),
          constant "COMPOSE_PROBES" (get u "compose_probe"),
          constant "SPECIAL_COUNT" (get t "special_count"),
          G.constant G.Int "PREFIX_LENGTH" (G.int (length prefix)),
          G.constant G.Int "SUFFIX_LENGTH" (G.int (length suffix)),
          array "BYTE_IDS" bytes,
          array "PREFIX" prefix,
          array "SUFFIX" suffix
        ]
