-- | Phase 3. Command and response.
--
-- The world is one Mealy machine that owns the 'World' token and
-- answers the commands of a protocol. The type of a response depends
-- on its command. A program is pure code. It is a function from a
-- state to a 'Step', which is one command and a function from its
-- response to the next state. 'close' runs a program against the
-- world.
--
-- The 'Quit' command gives the program a halt path.
--
-- Defect: the state of a program is its program counter, written by
-- hand. A program gives one command for each step.
module Phase3
  ( main,
    Echo (..),
    echo,
  )
where

--------------------------------------------------------------------------------

import Data.Void (absurd)
import Phase3.Console (Command (..), console)
import Phase3.Program (Program, Step (..), close)
import Phase3.World (run)

--------------------------------------------------------------------------------

main :: IO ()
main = run Reading (close console echo)

data Echo
  = Reading
  | Printing String
  | Stopping

-- | Reads a line and writes it back. Stops when the line is @quit@.
echo :: Program Command Echo
echo = \case
  Reading ->
    Step GetStrLn (\line -> if line == "quit" then Stopping else Printing line)
  Printing line -> Step (PutStrLn line) (\() -> Reading)
  Stopping -> Step Quit absurd
