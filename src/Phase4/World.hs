{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE UnboxedTuples #-}

-- | The unsafe layer. This module takes the @State# RealWorld@ token
-- out of 'IO'. Each effect is a Mealy machine with the token as its
-- state. 'liftIO' makes such a machine from a function in 'IO'.
--
-- The token holds no data. Its purpose is to fix the order of the
-- effects. A linear function must use the token one time, so each
-- effect depends on the effect before it.
module Phase4.World
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
import Phase4.Lens (Lens (..), Mealy, Moore, Multiplicity (..), mealy)
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
liftIO :: (i -> IO o) -> Mealy 'One World (Ur i) (Ur o)
liftIO f = mealy $ \world (Ur i) -> perform (f i) world

--------------------------------------------------------------------------------

-- | Steps a closed system that has no input and no output. Its state
-- is the token and a second state, which starts at the given value.
--
-- The loop stops only when an effect throws an exception. An effect
-- such as @exitSuccess@ uses that to stop the program.
run :: forall t. t -> Moore 'One (World, Ur t) () () -> IO ()
run initial machine =
  IO (\s -> case loop (World s, Ur initial) of (World s', Ur _) -> (# s', () #))
  where
    loop :: (World, Ur t) %1 -> (World, Ur t)
    loop state = case runLens machine state of
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
