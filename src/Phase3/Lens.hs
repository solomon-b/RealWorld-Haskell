-- | Linear lenses, and Moore and Mealy machines as lenses.
module Phase3.Lens
  ( -- * Lens
    Lens (..),
    compose,

    -- * Moore
    Moore,

    -- * Mealy
    Mealy,
    mealy,
    runMealy,
  )
where

--------------------------------------------------------------------------------

-- | A linear lens. It uses @s@ one time. It gives a view @a@ and an
-- update that the caller must use one time.
newtype Lens s t a b = Lens {runLens :: s %1 -> (a, b %1 -> t)}

-- | Puts the second lens inside the view of the first lens.
compose :: Lens s t a b -> Lens a b c d -> Lens s t c d
compose (Lens f) (Lens g) = Lens $ \s -> case f s of
  (a, update) -> case g a of
    (c, update') -> (c, \d -> update (update' d))

--------------------------------------------------------------------------------

-- | A Moore machine with state @s@, input @i@, and output @o@. The
-- output depends only on the state.
type Moore s i o = Lens s s o i

--------------------------------------------------------------------------------

-- | A Mealy machine with state @s@, input @i@, and output @o@. The
-- output depends on the state and the input.
type Mealy s i o = Lens (s, i) s o ()

mealy :: (s %1 -> i %1 -> (o, s)) -> Mealy s i o
mealy f = Lens $ \(s, i) -> case f s i of
  (o, s') -> (o, \() -> s')

runMealy :: Mealy s i o -> s %1 -> i %1 -> (o, s)
runMealy (Lens f) s i = case f (s, i) of
  (o, next) -> (o, next ())
