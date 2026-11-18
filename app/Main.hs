module Main (main) where

--------------------------------------------------------------------------------

import RealWorld.Lens (Lens (..), Moore, compose, lmap, moore, rmap)
import RealWorld.World (Ur (..), World, run)
import RealWorld.World qualified as World

--------------------------------------------------------------------------------

main :: IO ()
main = run echo

-- | The console as a Moore machine. The observation reads a line. The
-- transition writes a line.
console :: Moore World (Ur String) (Ur String)
console =
  moore
    (lmap (\() -> Ur ()) World.getLine)
    (rmap (\(Ur ()) -> ()) World.putStrLn)

-- | Connects the output of a machine to its input.
feedback :: Lens a a () ()
feedback = Lens $ \a -> ((), \() -> a)

echo :: Moore World () ()
echo = console `compose` feedback
