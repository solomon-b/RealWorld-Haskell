-- | Linear lenses, and Moore machines as lenses.
module Phase1.Lens
  ( -- * Lens
    Lens (..),

    -- * Moore
    Moore,
  )
where

--------------------------------------------------------------------------------

-- | A linear lens. It uses @s@ one time. It gives a view @a@ and an
-- update that the caller must use one time.
newtype Lens s t a b = Lens {runLens :: s %1 -> (a, b %1 -> t)}

-- | A Moore machine with state @s@, input @i@, and output @o@. The
-- output depends only on the state.
type Moore s i o = Lens s s o i
