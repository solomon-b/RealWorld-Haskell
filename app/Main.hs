{-# OPTIONS_GHC -Wno-unused-imports #-}

module Main (main) where

--------------------------------------------------------------------------------

import Phase1 qualified
import Phase2 qualified
import Phase3 qualified

--------------------------------------------------------------------------------

-- | Runs one phase. Remove the comment marker from the phase to run,
-- and put one on the others.
main :: IO ()
main =
  -- Phase1.main
  -- Phase2.main
  Phase3.main
