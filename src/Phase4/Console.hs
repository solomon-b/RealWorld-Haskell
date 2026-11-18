{-# LANGUAGE DataKinds #-}

-- | The console protocol, and the machine that answers it.
module Phase4.Console
  ( -- * Protocol
    Command (..),

    -- * World
    interpret,
    console,
  )
where

--------------------------------------------------------------------------------

import Data.Void (Void)
import Phase4.Lens (Mealy, Multiplicity (..))
import Phase4.World (Ur, World, liftIO)
import System.Exit (exitSuccess)

--------------------------------------------------------------------------------

-- | A console command. The type parameter is the type of the response
-- to that command.
data Command r where
  PutStrLn :: String -> Command ()
  GetStrLn :: Command String
  -- | No response comes back, because the program stops.
  Quit :: Command Void

--------------------------------------------------------------------------------

-- | Does one command in 'IO'.
interpret :: Command r -> IO r
interpret = \case
  PutStrLn line -> putStrLn line
  GetStrLn -> getLine
  Quit -> exitSuccess

-- | The world side of the protocol. It takes a command and gives the
-- response to that command.
console :: Mealy 'One World (Ur (Command r)) (Ur r)
console = liftIO interpret
