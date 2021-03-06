{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
module Main ( main ) where

import Data.Algorithm.Diff
import Data.Algorithm.DiffOutput
import Data.Function ( (&) )
import System.FilePath ( takeBaseName, replaceExtension )
import Test.Tasty ( defaultMain, TestTree, testGroup )
import Test.Tasty.Golden ( findByExtension, goldenVsStringDiff )
import Test.Tasty.Golden.Advanced ( goldenTest )

import qualified Data.ByteString as BS
import qualified Data.Text.IO as StrictText
import qualified Data.Text.Lazy.Encoding as LazyText
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified Data.Text.Prettyprint.Doc.Render.Text as Pretty
import qualified Dhall.Core
import qualified Distribution.PackageDescription.Parsec as Cabal
import qualified Distribution.PackageDescription.PrettyPrint as Cabal
import qualified Distribution.Verbosity as Cabal

import CabalToDhall ( cabalToDhall, parseGenericPackageDescriptionThrows )
import DhallLocation ( DhallLocation ( DhallLocation ) )
import DhallToCabal ( dhallToCabal )


  
main :: IO ()
main =
  defaultMain =<< goldenTests


preludeLocation :: Dhall.Core.Import
preludeLocation =
  Dhall.Core.Import
    { Dhall.Core.importHashed =
        Dhall.Core.ImportHashed
          { Dhall.Core.hash =
              Nothing
          , Dhall.Core.importType =
              Dhall.Core.Local
                Dhall.Core.Here
                ( Dhall.Core.File
                   ( Dhall.Core.Directory [ "dhall", "..", ".." ] )
                   "prelude.dhall"
                )
          }
    , Dhall.Core.importMode =
        Dhall.Core.Code
    }


typesLocation :: Dhall.Core.Import
typesLocation =
  Dhall.Core.Import
    { Dhall.Core.importHashed =
        Dhall.Core.ImportHashed
          { Dhall.Core.hash =
              Nothing
          , Dhall.Core.importType =
              Dhall.Core.Local
                Dhall.Core.Here
                ( Dhall.Core.File
                   ( Dhall.Core.Directory [ "dhall", "..", ".." ] )
                   "types.dhall"
                )
          }
    , Dhall.Core.importMode =
        Dhall.Core.Code
    }


goldenTests :: IO TestTree
goldenTests = do
  -- Note: must remain in sync with the layout options in
  -- cabal-to-dhall/Main.hs, so that test output is easy to generate
  -- at the command line.
  let layoutOpts = Pretty.defaultLayoutOptions
        { Pretty.layoutPageWidth = Pretty.AvailablePerLine 80 1.0 }
      dhallLocation = DhallLocation preludeLocation typesLocation

  dhallFiles <-
    findByExtension [ ".dhall" ] "golden-tests/dhall-to-cabal"
  cabalFiles <-
    findByExtension [ ".cabal" ] "golden-tests/cabal-to-dhall"

  return
    $ testGroup "golden tests"
      [ testGroup "dhall-to-cabal"
          [ goldenTest
              ( takeBaseName dhallFile )
              ( Cabal.readGenericPackageDescription Cabal.normal cabalFile )
              ( StrictText.readFile dhallFile >>= dhallToCabal dhallFile  )
              ( \ ( Cabal.showGenericPackageDescription -> exp ) ( Cabal.showGenericPackageDescription -> act ) -> do
                  if exp == act then
                      return Nothing
                  else do
                    putStrLn $ "Diff between expected " ++ cabalFile ++
                               " and actual " ++ dhallFile ++ " :"
                    let gDiff = getGroupedDiff (lines exp) (lines act)
                    putStrLn $ ppDiff gDiff
                    return $ Just "Generated .cabal file does not match input"
              )
              ( Cabal.writeGenericPackageDescription cabalFile )
          | dhallFile <- dhallFiles
          , let cabalFile = replaceExtension dhallFile ".cabal"
          ]
     , testGroup "cabal-to-dhall"
         [ goldenVsStringDiff
             ( takeBaseName cabalFile )
             ( \ ref new -> [ "diff", "-u", ref, new ] )
             dhallFile
             ( BS.readFile cabalFile >>= parseGenericPackageDescriptionThrows
                 & fmap ( LazyText.encodeUtf8 . Pretty.renderLazy
                        . Pretty.layoutSmart layoutOpts . Pretty.pretty
                        . cabalToDhall dhallLocation
                        )
             )
         | cabalFile <- cabalFiles
         , let dhallFile = replaceExtension cabalFile ".dhall"
         ]
    ]
