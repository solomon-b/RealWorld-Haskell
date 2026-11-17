module Main (main) where

--------------------------------------------------------------------------------

import Hedgehog ((===))
import Hedgehog qualified
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Hspec (Spec, describe, hspec, it)
import Test.Hspec.Hedgehog (hedgehog)

--------------------------------------------------------------------------------

main :: IO ()
main = hspec spec

-- TODO: Replace this placeholder with tests of the library.
spec :: Spec
spec =
  describe "reverse" $
    it "is an involution" $
      hedgehog $ do
        xs <- Hedgehog.forAll $ Gen.list (Range.linear 0 100) (Gen.int Range.linearBounded)
        reverse (reverse xs) === xs
