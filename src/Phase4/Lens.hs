{-# LANGUAGE DataKinds #-}

-- | One lens type for linear and for plain lenses, and Moore and Mealy
-- machines as lenses.
--
-- A function arrow has a multiplicity. It says how many times the
-- function can use its argument. @a %1 -> b@ is @a %'One -> b@, and
-- @a -> b@ is @a %'Many -> b@. The lens has that multiplicity as a
-- parameter.
module Phase4.Lens
  ( -- * Lens
    Lens (..),
    Multiplicity (..),
    lens,
    compose,
    tensor,

    -- * Moore
    Moore,

    -- * Mealy
    Mealy,
    mealy,
    runMealy,
  )
where

--------------------------------------------------------------------------------

import GHC.Exts (Multiplicity (..))

--------------------------------------------------------------------------------

-- | A lens with multiplicity @m@. It gives a view @a@ and an update
-- from @b@ to @t@.
--
-- At @'One@ the lens is linear. It uses @s@ one time, and the caller
-- must use the update one time. The machines that hold the token have
-- this multiplicity.
--
-- At @'Many@ the lens is plain. The pure machines have this
-- multiplicity, so they can use a value two times or drop it.
--
-- In Poly, a lens is a map @s y^t ⇒ a y^b@.
newtype Lens (m :: Multiplicity) s t a b = Lens {runLens :: s %m -> (a, b %m -> t)}

-- | Makes a plain lens from a view function and an update function.
lens :: (s -> a) -> (s -> b -> t) -> Lens 'Many s t a b
lens get set = Lens $ \s -> (get s, \b -> set s b)

-- | Composition of maps in Poly. The second lens goes inside the view
-- of the first lens.
--
-- A function for every @m@ must be correct at @'One@. Thus it uses each
-- value one time.
compose :: Lens m s t a b -> Lens m a b c d -> Lens m s t c d
compose (Lens f) (Lens g) = Lens $ \s -> case f s of
  (a, update) -> case g a of
    (c, update') -> (c, \d -> update (update' d))

-- | The parallel product ⊗ of Poly, on maps. It runs two lenses side
-- by side. For machines, each one keeps its own state, and both step
-- one time for each step of the pair.
--
-- The pairs in the type are ⊗ on the monomial interfaces:
-- @o y^i ⊗ o' y^i' = (o, o') y^(i, i')@.
tensor :: Lens m s t a b -> Lens m s' t' a' b' -> Lens m (s, s') (t, t') (a, a') (b, b')
tensor (Lens f) (Lens g) = Lens $ \(s, s') -> case f s of
  (a, update) -> case g s' of
    (a', update') -> ((a, a'), \(b, b') -> (update b, update' b'))

--------------------------------------------------------------------------------

-- | A Moore machine with state @s@, input @i@, and output @o@. The
-- output depends only on the state.
type Moore m s i o = Lens m s s o i

--------------------------------------------------------------------------------

-- | A Mealy machine with state @s@, input @i@, and output @o@. The
-- output depends on the state and the input.
type Mealy m s i o = Lens m (s, i) s o ()

mealy :: (s %m -> i %m -> (o, s)) -> Mealy m s i o
mealy f = Lens $ \(s, i) -> case f s i of
  (o, s') -> (o, \() -> s')

runMealy :: Mealy m s i o -> s %m -> i %m -> (o, s)
runMealy (Lens f) s i = case f (s, i) of
  (o, next) -> (o, next ())
