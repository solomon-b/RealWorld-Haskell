-- | The wiring that gives a pure Moore machine a protocol as its outer
-- interface.
module Phase4.Wiring
  ( into,
  )
where

--------------------------------------------------------------------------------

import Phase4.Moore (Moore, observe, transition)
import Phase4.Program (Program, Step (..))

--------------------------------------------------------------------------------

-- | Composes a machine with an outer wiring. The result is a program
-- whose state is the state of the machine.
--
-- The wiring takes the output of the machine. It gives one command,
-- and a function from the response to the input of the machine.
--
-- This is composition in Poly, where the second map goes to the
-- polynomial @p@ of a protocol:
--
-- @
-- Syˢ ⇒ Oyᴵ ⇒ p
-- @
into :: Moore s i o -> (o -> Step f i) -> Program f s
into machine wiring s = case wiring (observe machine s) of
  Step command continue ->
    Step command (\response -> transition machine s (continue response))
