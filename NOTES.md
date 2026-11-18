# Notes: linear machines as an alternative to monadic IO

Last update: 2026-11-17.

The repo is a workshop for a blog post. The post replaces monadic IO with
linear Moore and Mealy machines and shows effectful programs in that
paradigm. The aim is an alternative with power similar to monads.

## The design

The design comes from a conversation with Reed Mullanix.

One linear lens type is the base. Moore and Mealy machines are aliases of it.

```haskell
newtype Lens s t a b = Lens {runLens :: s %1 -> (a, b %1 -> t)}

type Moore s i o = Lens s s o i
type Mealy s i o = Lens (s, i) s o ()
```

These agree with the Poly definitions.

```
Moore S I O = monomial S S       ⇒ monomial O I
Mealy S I O = monomial (S × I) S ⇒ monomial O ⊤
```

In Agda the base map and the fiber map are separate functions. In the linear
version they are one function, because the state can be used only one time.

Each effect is a Mealy machine. Its state is the token. `liftIO` makes such
a machine from a function in `IO`.

```haskell
liftIO :: (i -> IO o) -> Mealy World (Ur i) (Ur o)

getLine :: Mealy World (Ur ()) (Ur String)
getLine = liftIO (\() -> IO.getLine)

putStrLn :: Mealy World (Ur String) (Ur ())
putStrLn = liftIO IO.putStrLn
```

`mealy` and `runMealy` convert between a Mealy machine and its step function.

```haskell
mealy    :: (s %1 -> i %1 -> (o, s)) -> Mealy s i o
runMealy :: Mealy s i o -> s %1 -> i %1 -> (o, s)
```

A program is a Moore machine on the same state. It is built by composition.

```haskell
console :: Moore World (Ur String) (Ur String)
console =
  moore
    (lmap (\() -> Ur ()) World.getLine)
    (rmap (\(Ur ()) -> ()) World.putStrLn)

echo :: Moore World () ()
echo = console `compose` feedback
```

`feedback` is a wiring lens. It connects the output of a machine to its input.

### `moore` joins two Mealy machines

```haskell
moore :: Mealy s () o -> Mealy s i () -> Moore s i o
```

The first machine gives the observation. The second gives the transition.
This is not a standard construction. It was written as glue. A possible
reading in Poly, not checked, is that the Moore interface is a composite.

```
O y^I = O y ◁ y^I
```

`Mealy s () o` is `S → O × S`, a coalgebra for `O y`. `Mealy s i ()` is
`S → S^I`, a coalgebra for `y^I`. Two coalgebras on the same state compose to
a coalgebra for the composite.

In an ordinary Moore machine the readout is `S → O`. Here the readout returns
a state, because it uses the state one time.

## Files

| File | Content |
| --- | --- |
| `src/RealWorld/Lens.hs` | `Lens`, `compose`, `Moore`, `moore`, `Mealy`, `mealy`, `runMealy`, `lmap`, `rmap` |
| `src/RealWorld/World.hs` | The unsafe layer: `World`, `Ur`, `liftIO`, `getLine`, `putStrLn`, `run` |
| `app/Main.hs` | `console`, `feedback`, `echo` |

Run echo in the dev shell (`nix develop`) with `cabal run realworld-haskell`.
It reads a line and writes it back. It gives no prompt.

## About the token

- `RealWorld` is a type with no values. It is only a tag.
- `State# RealWorld` is the token. It is a primitive type with no constructor
  and zero size. `IO` is a state monad that threads it.
- The token exists only for sequencing. Each effect takes a token and returns
  a new one, so each effect depends on the effect before it.
- `State# RealWorld` is unlifted, so it cannot be a parameter of `Lens`.
  `data World = World (State# RealWorld)` is a box that makes it lifted.
- `World.hs` does not export the `World` constructor or `perform`. No outside
  code can open the token.
- `World.hs` exports `liftIO`. Any module can make a machine from any function
  in `IO`. That is the one way to add an effect.
- The only unsafe cast is in `perform`. GHC checks linearity in all other
  code.
- A token can be made from nothing with `realWorld#` or `runRW#`. Thus a token
  is not proof of ownership. Linearity and the hidden constructor give the
  discipline.
- A `Mealy World i o` has the same shape as `i -> IO o`, uncurried.

## Known defects

- The driver `run` has no halt path. The loop stops only when an effect throws
  an exception, for example at end of file.
- `console` must convert between `()` and `Ur ()` with `lmap` and `rmap`,
  because `liftIO` gives `Ur ()` and `moore` takes `()`.
- No test covers the library. The test suite has one placeholder property.

## Ideas for later

From the conversation with Reed:

- The tensor of two lenses is `Lens (s0, s1) (t0, t1) (a0, a1) (b0, b1)`. The
  tensor means that the two sides run in parallel. Effects are in order along
  each side only.
- Two machines on `World` need two tokens to be tensored. One idea is to
  divide the world into smaller tokens, one for each protocol, with different
  machines for each.
- A second idea is a `dup` lens that forks the world. The coproduct of lenses
  could be the correct structure for that.

From the first spike:

- An output of `Either r o` can mean that a machine has finished. That gives a
  form of sequencing and a halt path.
- The fixed point of a machine that can halt is a free monad.
- monoidal-functors has the classes for the tensor. Version 0.3.0.0 has a
  `laws` library, but nixpkgs has 0.2.3.0.

## History

Two earlier versions are in `git stash`.

- "spike v1" has a `World` token with functions of the form
  `World %1 -> (a, World)`, a `Borrow` machine that passes the token on its
  wires, and `andThen`. It was `IO` with another name.
- "spike v2" has GHC's `RealWorld` as the machine state with no token, and
  `unsafePerformIO` on each effect. GHC gives no guarantee for its order of
  effects.

## References

- cofree-bot, `machines-coalgebras`:
  https://github.com/cofree-coffee/cofree-bot/tree/main/machines-coalgebras
- Lensy Moore: https://blog.cofree.coffee/2024-07-02-lensy-moore/
- monoidal-functors: https://github.com/solomon-b/monoidal-functors/
