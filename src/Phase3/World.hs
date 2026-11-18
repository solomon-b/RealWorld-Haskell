{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}

-- | The unsafe layer. This module takes the @State# RealWorld@ token
-- out of 'IO'. Each effect is a Mealy machine with the token as its
-- state. 'liftIO' makes such a machine from a function in 'IO'.
--
-- The token holds no data. Its purpose is to fix the order of the
-- effects. A linear function must use the token one time, so each
-- effect depends on the effect before it.
module Phase3.World
  ( -- * World
    World,
    liftIO,

    -- * Unrestricted Values
    Ur (..),

    -- * Driver
    run,
  )
where

--------------------------------------------------------------------------------

import GHC.Base (IO (..))
import GHC.Exts (RealWorld, State#)
import Phase3.Lens (Lens (..), Mealy, Moore, mealy)
import Unsafe.Coerce (unsafeCoerce)

--------------------------------------------------------------------------------

-- | The token that 'IO' threads through each primitive operation.
data World = World (State# RealWorld)

-- | A value that linear code can use any number of times.
data Ur a where
  Ur :: a -> Ur a

--------------------------------------------------------------------------------

-- | Makes a machine from a function in 'IO'. The machine does the
-- effect one time for each input.
liftIO :: (i -> IO o) -> Mealy World (Ur i) (Ur o)
liftIO f = mealy $ \world (Ur i) -> perform (f i) world

--------------------------------------------------------------------------------

-- | Steps a machine that has no input and no output.
--
-- TODO: The machine has no halt path. This loop stops only when an
-- effect throws an exception.
run :: Moore World () () -> IO ()
run machine = IO (\s -> case loop (World s) of World s' -> (# s', () #))
  where
    loop :: World %1 -> World
    loop world = case runLens machine world of
      ((), next) -> loop (next ())

--------------------------------------------------------------------------------

-- | Runs one 'IO' action against the token.
perform :: forall a. IO a -> World %1 -> (Ur a, World)
perform (IO f) = toLinear go
  where
    go :: World -> (Ur a, World)
    go (World s) = case f s of (# s', a #) -> (Ur a, World s')

-- | The primitive operations in "GHC.Exts" have unrestricted arrows.
-- This cast tells GHC that 'perform' uses the token one time.
toLinear :: (a -> b) -> (a %1 -> b)
toLinear = unsafeCoerce
