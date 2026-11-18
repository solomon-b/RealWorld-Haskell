-- | Linear lenses, and Moore and Mealy machines as lenses.
module RealWorld.Lens
  ( -- * Lens
    Lens (..),
    compose,

    -- * Moore
    Moore,
    moore,

    -- * Mealy
    Mealy,
    mealy,
    runMealy,
    lmap,
    rmap,
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

-- | Makes a Moore machine from two Mealy machines on the same state.
-- The first gives the observation. The second gives the transition.
moore :: Mealy s () o -> Mealy s i () -> Moore s i o
moore observe transition = Lens $ \s -> case runMealy observe s () of
  (o, s') -> (o, \i -> case runMealy transition s' i of ((), s'') -> s'')

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

-- | Changes the input of a Mealy machine.
lmap :: (i' %1 -> i) -> Mealy s i o -> Mealy s i' o
lmap f machine = mealy $ \s i -> runMealy machine s (f i)

-- | Changes the output of a Mealy machine.
rmap :: (o %1 -> o') -> Mealy s i o -> Mealy s i o'
rmap f machine = mealy $ \s i -> case runMealy machine s i of
  (o, s') -> (f o, s')
