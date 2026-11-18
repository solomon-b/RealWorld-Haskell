-- | Pure Moore machines as lenses, from the Lensy Moore post. These
-- lenses are not linear.
--
-- https://blog.cofree.coffee/2024-07-02-lensy-moore/
module Phase4.Moore
  ( -- * Moore
    Moore,
    observe,
    transition,
    tensor,

    -- * Lens
    view,
    set,
  )
where

--------------------------------------------------------------------------------

import Data.Functor.Const (Const (..))
import Data.Functor.Identity (Identity (..))
import Lens.Micro (Lens, lens)

--------------------------------------------------------------------------------

view :: Lens s t a b -> s -> a
view l s = getConst $ l Const s

set :: Lens s t a b -> s -> b -> t
set l s b = runIdentity $ l (\_ -> Identity b) s

--------------------------------------------------------------------------------

-- | Syˢ ⇒ Oyᴵ
type Moore s i o = Lens s s o i

observe :: Moore s i o -> s -> o
observe m s = view m s

transition :: Moore s i o -> s -> i -> s
transition m s i = set m s i

-- | Runs two machines in parallel as one machine.
tensor :: Moore s i o -> Moore t i' o' -> Moore (s, t) (i, i') (o, o')
tensor m n =
  let observe' (s, t) = (observe m s, observe n t)
      transition' (s, t) (a, a') = (transition m s a, transition n t a')
   in lens observe' transition'
