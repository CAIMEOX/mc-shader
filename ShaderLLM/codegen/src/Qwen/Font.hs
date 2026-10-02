{-# LANGUAGE OverloadedStrings #-}

module Qwen.Font (compileFonts) where

import Codec.Picture
import Data.Aeson
import Data.Bits
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (chr)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Data.Vector.Storable qualified as VS
import Data.Word
import Numeric (readHex)
import Qwen.Tokenizer (uintTexture)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

compileFonts :: FilePath -> FilePath -> IO ()
compileFonts model output = do
  createDirectoryIfMissing True output
  let cps = [cp | cp <- [32 .. 65535], cp < 0xd800 || cp > 0xdfff]
      rows = map (\row -> row ++ replicate (256 - length row) 0) (chunks 256 cps)
      width = 1024
      height = length rows * 4
      physical = VS.fromList (concat rows)
      marker cp
        | cp == 0xe100 = (0, 0, 237)
        | cp == 0xe101 = (0, 0, 236)
        | cp == 0xe102 = (0, 0, 235)
        | cp >= 0xe000 && cp < 0xe020 = (fromIntegral (cp - 0xe000), 0, 239)
        | otherwise = (fromIntegral (cp .&. 255), fromIntegral (cp `shiftR` 8), 239)
      image =
        generateImage
          ( \x y ->
              let i = (y `div` 4) * 256 + x `div` 4
                  (r, g, b) = if i < VS.length physical then marker (physical VS.! i) else (0, 0, 0)
               in PixelRGBA8 r g b 247
          )
          width
          height
  writePng (output </> "wire.png") image
  BL.writeFile
    (output </> "wire.json")
    ( encode
        ( object
            [ "providers"
                .= [ object
                       [ "type" .= ("bitmap" :: String),
                         "file" .= ("qwen:font/wire.png" :: String),
                         "height" .= (4 :: Int),
                         "ascent" .= (4 :: Int),
                         "chars" .= map (T.pack . map chr) rows
                       ]
                   ]
            ]
        )
    )
  bytes <- BS.readFile (model </> "unifont.hex")
  let glyphs = M.fromList [parseLine line | line <- BC.lines bytes, not (BS.null line)]
      wordCount = 0x110000 * 8
      glyphWords = VS.generate wordCount $ \i ->
        let cp = i `div` 8
            rowPair = i `mod` 8
            bitmap = M.findWithDefault (replicate 16 0) cp glyphs
         in (fromIntegral (bitmap !! (rowPair * 2)) `shiftL` 16) .|. fromIntegral (bitmap !! (rowPair * 2 + 1)) :: Word32
  spec <- uintTexture (output </> "glyphs.png") 4096 glyphWords
  BL.writeFile (output </> "font-layout.json") (encode spec)
  where
    chunks _ [] = []
    chunks n xs = let (a, b) = splitAt n xs in a : chunks n b
    hex s = case readHex s of [(x, "")] -> x; _ -> error "Invalid unihex glyph"
    parseLine line = case BC.split ':' line of
      [a, b] ->
        let code = hex (BC.unpack a)
            bitmap = BC.unpack b
            stride = length bitmap `div` 16
            values = [(hex (take stride (drop (row * stride) bitmap)) :: Int) `shiftL` (if stride == 2 then 8 else 0) | row <- [0 .. 15]]
         in (code, values)
      _ -> error "Invalid unihex line"
