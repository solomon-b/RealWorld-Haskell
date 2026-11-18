-- | The functions that give 'Tree' a @do@ notation, through the
-- @QualifiedDo@ extension. Import this module qualified, and write
-- @Tree.do@.
--
-- A @do@ block of this kind needs no 'Monad' instance. Each statement
-- is a command, and the last line is a 'Tree'.
module Phase5.Tree.Do
  ( (>>=),
    (>>),
  )
where

--------------------------------------------------------------------------------

import Phase5.Tree (Tree (..))
import Prelude hiding ((>>), (>>=))

--------------------------------------------------------------------------------

-- | Does a command and continues with its response. This is the 'Tree'
-- constructor.
(>>=) :: f r -> (r -> Tree f) -> Tree f
(>>=) = Tree

-- | Does a command and continues with no use of its response.
(>>) :: f r -> Tree f -> Tree f
command >> rest = Tree command (\_ -> rest)
