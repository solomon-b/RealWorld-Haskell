-- | Pure programs that speak a protocol, and the loop that runs a
-- program against the world.
module Phase3.Program
  ( -- * Program
    Step (..),
    Program,

    -- * Closed Loop
    close,
  )
where

--------------------------------------------------------------------------------

import Phase3.Lens (Lens (..), Mealy, Moore, runMealy)
import Phase3.World (Ur (..), World)

--------------------------------------------------------------------------------

-- | One step of a program that speaks the protocol @f@. It holds a
-- command and a function from the response to the next state.
--
-- The response type @r@ is hidden. Each step chooses its own @r@, and
-- the function must accept the response type of its command.
data Step f t where
  Step :: f r -> (r -> t) -> Step f t

-- | A program with state @t@. The state says where the program is.
--
-- A program is pure. It has ordinary arrows, because only the world
-- needs linearity.
type Program f t = t -> Step f t

--------------------------------------------------------------------------------

-- | Runs a program against a world machine. Each step of the result
-- takes one command from the program, gives it to the world, and gives
-- the response to the program.
--
-- The result has no input and no output. Its state is the token and
-- the state of the program.
close ::
  (forall r. Mealy World (Ur (f r)) (Ur r)) ->
  Program f t ->
  Moore (World, Ur t) () ()
close world program = Lens $ \(token, Ur t) -> case program t of
  Step command continue -> case runMealy world token (Ur command) of
    (Ur response, token') -> ((), \() -> (token', Ur (continue response)))
