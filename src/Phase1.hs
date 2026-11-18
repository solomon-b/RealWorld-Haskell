-- | Phase 1. The token is a value, and each effect is a function on it.
--
-- A Moore machine is a linear lens. One Moore machine owns the 'World'
-- token in its state. The
-- observation and the transition call the effects directly.
--
-- Defect: an effect has the type @World %1 -> (a, World)@. That is the
-- state monad of 'IO' with another name. The machine holds the token,
-- but it does not manage the state.
module Phase1
  ( main,
    echo,
  )
where

--------------------------------------------------------------------------------

import Phase1.Console qualified as Console
import Phase1.Lens (Lens (..), Moore)
import Phase1.World (Ur (..), World, run)

--------------------------------------------------------------------------------

main :: IO ()
main = run (Ur 1,) echo

-- | Reads a line in the observation. Prints the line with its number
-- in the transition.
echo :: Moore (Ur Int, World) () ()
echo = Lens $ \(Ur n, world) -> case Console.getLine world of
  (Ur line, world') ->
    ( (),
      \() -> (Ur (n + 1), Console.putStrLn (show n <> ": " <> line) world')
    )
