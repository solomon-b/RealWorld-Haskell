-- | Phase 2. One linear lens type, with Moore and Mealy machines as
-- aliases of it.
--
-- Each effect is a Mealy machine with the 'World' token as its state.
-- 'liftIO' makes such a machine from a function in 'IO'. A program is a
-- Moore machine on the same state, built by composition.
--
-- Defect: a @Mealy World i o@ has the same shape as @i -> IO o@. The
-- program is a machine on 'World', so two programs cannot be tensored.
-- The driver has no halt path.
module Phase2
  ( main,
    console,
    feedback,
    echo,
  )
where

--------------------------------------------------------------------------------

import Phase2.Lens (Lens (..), Moore, compose, lmap, rmap, runThen)
import Phase2.World (Ur (..), World, run)
import Phase2.World qualified as World

--------------------------------------------------------------------------------

main :: IO ()
main = run echo

-- | The console as a Moore machine. The observation reads a line. The
-- transition writes a line.
console :: Moore World (Ur String) (Ur String)
console =
  runThen
    (lmap (\() -> Ur ()) World.getLine)
    (rmap (\(Ur ()) -> ()) World.putStrLn)

-- | Connects the output of a machine to its input.
feedback :: Lens a a () ()
feedback = Lens $ \a -> ((), \() -> a)

echo :: Moore World () ()
echo = console `compose` feedback
