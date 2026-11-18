{-# LANGUAGE QualifiedDo #-}

-- | Phase 5. Tree.
--
-- A 'Tree' is a program with no state type. It is the fixed point of
-- 'Step'. Each node is a command, and a function from the response to
-- the rest of the program. So the program counter of phase 3 is no
-- longer written by hand.
--
-- The @QualifiedDo@ extension gives a tree a @do@ notation with no
-- 'Monad' instance. The bind of the notation is the 'Tree'
-- constructor.
--
-- 'unroll' makes a tree a 'Program', so 'annihilate' runs it against
-- the world as in phase 3.
--
-- Defect: a tree has no result. A piece of a program that gives a
-- value cannot be used in the middle of another program.
module Phase5
  ( main,
    runTree,
    stop,
    greet,
    echo,
    Echo (..),
    echoProgram,
    unfolded,
  )
where

--------------------------------------------------------------------------------

import Data.Void (absurd)
import Phase5.Console (Command (..), console)
import Phase5.Program (Program, Step (..), annihilate)
import Phase5.Tree (Tree (..), unfold, unroll)
import Phase5.Tree.Do qualified as Tree
import Phase5.World (run)

--------------------------------------------------------------------------------

-- | Runs one demo. Remove the comment marker from the demo to run, and
-- put one on the other.
main :: IO ()
main = runTree greet

-- main = runTree unfolded

-- | Runs a tree against the console.
runTree :: Tree Command -> IO ()
runTree tree = run tree (annihilate unroll console)

--------------------------------------------------------------------------------
-- A program in do notation

-- | The tree that stops the program.
stop :: Tree Command
stop = Tree Quit absurd

-- | Asks for a name, greets, and then runs 'echo'.
greet :: Tree Command
greet = Tree.do
  PutStrLn "What is your name?"
  name <- GetStrLn
  PutStrLn ("hello " ++ name)
  echo

-- | Reads a line and writes it back. Stops when the line is @quit@.
echo :: Tree Command
echo = Tree.do
  line <- GetStrLn
  if line == "quit"
    then stop
    else Tree.do
      PutStrLn line
      echo

--------------------------------------------------------------------------------
-- The program of phase 3, as a tree

data Echo
  = Reading
  | Printing String
  | Stopping

-- | The echo program of phase 3, with its state written by hand.
echoProgram :: Program Command Echo
echoProgram = \case
  Reading ->
    Step GetStrLn (\line -> if line == "quit" then Stopping else Printing line)
  Printing line -> Step (PutStrLn line) (\() -> Reading)
  Stopping -> Step Quit absurd

-- | The tree of 'echoProgram'. It does the same as 'echo'.
unfolded :: Tree Command
unfolded = unfold echoProgram Reading
