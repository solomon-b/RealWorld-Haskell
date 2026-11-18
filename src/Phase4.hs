-- | Phase 4. Wiring diagrams.
--
-- The program is a pile of pure Moore machines from the Lensy Moore
-- post. The machines are joined with 'tensor' and wired with a plain
-- lens. 'into' then gives the pile the console protocol as its outer
-- interface, and the result is a 'Program' as in phase 3.
--
-- Defect: the pile gives one command for each step. The outer wiring
-- must choose one command from all the outputs of the pile.
module Phase4
  ( main,
    plus,
    delay,
    plusDelay,
    fibWiring,
    fib,
    outer,
  )
where

--------------------------------------------------------------------------------

import Data.Void (absurd)
import Lens.Micro (Lens, lens)
import Phase4.Console (Command (..), console)
import Phase4.Moore (Moore, tensor)
import Phase4.Program (Step (..), annihilate)
import Phase4.Wiring (into)
import Phase4.World (run)

--------------------------------------------------------------------------------

main :: IO ()
main = run (1, 0) (annihilate (fib `into` outer) console)

--------------------------------------------------------------------------------
-- The pile, from the post

-- | Int × y^Int => Int × y^(Int × Int)
plus :: Moore Int (Int, Int) Int
plus = lens id (\_ (x, y) -> x + y)

-- | Int × y^Int => Int × y^Int
delay :: Moore Int Int Int
delay = lens id (\_ y -> y)

-- | (ℤ × ℤ) y^ (ℤ × ℤ) ⇒ (ℤ × ℤ) y^ ((ℤ × ℤ) × ℤ)
plusDelay :: Moore (Int, Int) ((Int, Int), Int) (Int, Int)
plusDelay = plus `tensor` delay

fibWiring :: Lens (Int, Int) ((Int, Int), Int) Int ()
fibWiring =
  lens
    -- The Q output is wired to the outer interface's output:
    (\(_pout, qout) -> qout)
    -- The P and Q outputs are wired into the P input and
    -- the P output is wired into the Q input:
    (\(pout, qout) () -> ((pout, qout), pout))

-- | (ℤ × ℤ) y^ (ℤ × ℤ) ⇒ ℤ y^ Unit
fib :: Moore (Int, Int) () Int
fib = plusDelay . fibWiring

--------------------------------------------------------------------------------
-- The outer wiring

-- | Writes each number. Stops after the first number above 1000.
outer :: Int -> Step Command ()
outer n
  | n > 1000 = Step Quit absurd
  | otherwise = Step (PutStrLn (show n)) (\() -> ())
