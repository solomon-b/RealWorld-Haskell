{-# LANGUAGE DataKinds #-}

-- | The wiring that lets a tree drive a pure Moore machine.
module Phase5.Wiring
  ( drive,
  )
where

--------------------------------------------------------------------------------

import Phase5.Lens (Lens (..), Moore, Multiplicity (..))
import Phase5.Tree (Tree)

--------------------------------------------------------------------------------

-- | Makes a tree from a machine, an outer wiring, and a start state.
--
-- The wiring takes the output of the machine, and a function that
-- continues the program when it gets the next input of the machine.
-- Between the two, the wiring can do any number of commands.
--
-- The wiring takes a function because a tree has no result. With a
-- result, the wiring is a function from the output to a tree that ends
-- with the input.
drive :: Moore 'Many s i o -> (o -> (i -> Tree f) -> Tree f) -> s -> Tree f
drive machine wiring s = case runLens machine s of
  (o, next) -> wiring o (\i -> drive machine wiring (next i))
