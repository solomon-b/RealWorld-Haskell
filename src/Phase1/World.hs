{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}

-- | The unsafe layer. This module takes the @State# RealWorld@ token
-- out of 'IO' and gives it to linear code.
--
-- A linear function must use the token one time. Thus the data
-- dependency on the token fixes the order of the effects.
module Phase1.World
  ( -- * World
    World,
    perform,

    -- * Unrestricted Values
    Ur (..),

    -- * Driver
    run,
  )
where

--------------------------------------------------------------------------------

import GHC.Base (IO (..))
import GHC.Exts (RealWorld, State#)
import Phase1.Lens (Lens (..), Moore)
import Unsafe.Coerce (unsafeCoerce)

--------------------------------------------------------------------------------

-- | The token that 'IO' threads through each primitive operation.
data World = World (State# RealWorld)

-- | A value that linear code can use any number of times.
data Ur a where
  Ur :: a -> Ur a

--------------------------------------------------------------------------------

-- | Runs one 'IO' action against the token.
perform :: forall a. IO a -> World %1 -> (Ur a, World)
perform (IO f) = toLinear go
  where
    go :: World -> (Ur a, World)
    go (World s) = case f s of (# s', a #) -> (Ur a, World s')

--------------------------------------------------------------------------------

-- | Makes the initial state from the token, then steps the machine.
--
-- TODO: The machine has no halt path. This loop stops only when an
-- effect throws an exception.
run :: forall s. (World %1 -> s) -> Moore s () () -> IO ()
run initial machine =
  IO (\s -> case loop (initial (World s)) of World s' -> (# s', () #))
  where
    loop :: s %1 -> World
    loop state = case runLens machine state of
      ((), next) -> loop (next ())

--------------------------------------------------------------------------------

-- | The primitive operations in "GHC.Exts" have unrestricted arrows.
-- This cast tells GHC that 'perform' uses the token one time.
toLinear :: (a -> b) -> (a %1 -> b)
toLinear = unsafeCoerce
