-- | A program as a tree of interactions, with no state type.
module Phase5.Tree
  ( -- * Tree
    Tree (..),
    unroll,
    unfold,
  )
where

--------------------------------------------------------------------------------

import Phase5.Program (Program, Step (..))

--------------------------------------------------------------------------------

-- | A full program that speaks the protocol @f@. Each node holds a
-- command, and a function from the response to the rest of the
-- program.
--
-- A @'Step' f t@ is one layer that ends in a state @t@. A 'Tree' is
-- the layers nested. It is the fixed point of @'Step' f@. In Poly,
-- these are the trees of the polynomial of the protocol.
data Tree f where
  Tree :: f r -> (r -> Tree f) -> Tree f

-- | Takes one layer off a tree. This is a program whose state is the
-- tree, so a tree runs as any other program does.
unroll :: Program f (Tree f)
unroll (Tree command continue) = Step command continue

-- | Makes the tree of a program from a start state.
unfold :: Program f t -> t -> Tree f
unfold program t = case program t of
  Step command continue ->
    Tree command (\response -> unfold program (continue response))
