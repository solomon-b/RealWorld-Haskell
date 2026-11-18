-- | Console effects on the 'World' token.
module Phase1.Console
  ( -- * Console
    getLine,
    putStrLn,
  )
where

--------------------------------------------------------------------------------

import Phase1.World (Ur (..), World, perform)
import System.IO qualified as IO
import Prelude hiding (getLine, putStrLn)

--------------------------------------------------------------------------------

getLine :: World %1 -> (Ur String, World)
getLine = perform IO.getLine

putStrLn :: String -> World %1 -> World
putStrLn line world = case perform (IO.putStrLn line) world of
  (Ur (), world') -> world'
