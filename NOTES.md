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

## The command and response design

This is the current direction. It is the next step after the Lensy Moore post
and cofree-bot. The world is one machine that owns the token. The program is
pure code. A closed loop runs the program against the world.

Status: the protocol and the world side are built and not committed. The
program side is not built. Every claim about `Step`, `plug`, and the closed
loop is by hand and is not compiled.

### Where it started: annihilate

```agda
annihilate
  : ∀ {S T A B : Set}
  → Moore S A B
  → Mealy T B A
  → monomial S S ⊗ monomial T T ⇒ 𝕐
annihilate moore mealy = pair-machines moore mealy ⨟ₚ ⊗-second hom-to-𝕐 ⨟ₚ eval
```

In our types:

```haskell
annihilate :: Moore s a b -> Mealy t b a -> Lens (s, t) (s, t) () ()
annihilate world program = Lens $ \(s, t) -> case runLens world s of
  (b, next) -> case runMealy program t b of
    (a, t') -> ((), \() -> (next a, t'))
```

The Moore machine shows its output. The Mealy machine takes that output and
gives a command and its new state. The Moore machine makes its transition on
the command. The pairing must be Moore against Mealy. The Moore output does
not depend on the current input, and that breaks the cycle.

### Two consistent designs

Reed gave a protocol where the type of a response depends on the command.

```agda
data Command : Type where
  PutStrLn : String → Command
  GetStrLn : Command
  Quit : Command

Response : Command → Type
Response (PutStrLn s) = Unit
Response GetStrLn = String
Response Quit = Void
```

That dependency decides which side is the Moore machine.

**Design A. The world is the Moore machine.** `Response` is one ordinary sum
type. The world shows the response to the previous command, so its state
holds the last response, and it needs a first value such as `Started`.

```haskell
world   :: Moore (World, Ur Response) (Ur Command) (Ur Response)
program :: Mealy t (Ur Response) (Ur Command)
```

This uses only the current types, and `annihilate` is exactly the Agda. The
cost is that the types do not tie a response to its command, so the program
has a catch-all case. The standard Mealy to Moore conversion,
`delay :: Mealy s i o -> Moore (s, o) i o`, would build the world from
`liftIO interpret`.

**Design B. The response depends on the command.** The world cannot give a
response until it has seen the command, so the world is the Mealy machine.
The program gives the command first, so the program is the Moore side.

Design B is the choice. A Moore world with dependent responses would have to
store a response whose type changes at every step.

### The protocol and the world side (built)

`src/Phase3/Console.hs`:

```haskell
data Command r where
  PutStrLn :: String -> Command ()
  GetStrLn :: Command String
  Quit :: Command Void

interpret :: Command r -> IO r

console :: Mealy World (Ur (Command r)) (Ur r)
console = liftIO interpret
```

- Haskell cannot write a function from a value to a type. So `Response` is
  the type parameter `r` of `Command`. Each constructor states its own
  response type.
- An alternative makes `Response` visible. It is a type family over a `Tag`
  kind, with `interpret :: Command c -> IO (Response c)`. It needs `DataKinds`
  and `TypeFamilies`. The two forms carry the same information.
- The world side needed no new machinery. `console` is polymorphic in `r`.
- `interpret Quit` is `exitSuccess`, which has type `IO Void`. So the halt
  path is inside the protocol.
- All monadic `IO` of a program is in one function at the edge, `interpret`.

### Step (not built)

One step of a program says which command to do, and how to continue from the
response. A plain pair fails.

```haskell
program :: t -> (Command r, r -> t)
```

The `r` is one type for the whole function. But one state wants `GetStrLn`,
where `r` is `String`, and another wants `PutStrLn`, where `r` is `()`.

`Step` lets each step choose its own `r`, and hides it.

```haskell
data Step f t where
  Step :: f r -> (r -> t) -> Step f t
```

`f` is the protocol. `t` is the type of the next state. `r` is in both
arguments and not in the result type. The real version has `%1` on some
arrows.

These three values have different `r` inside and the same type.

```haskell
Step GetStrLn        (\line -> Printing line)   -- r is String
Step (PutStrLn line) (\()   -> Reading)         -- r is ()
Step Quit            absurd                     -- r is Void
```

The code that opens a `Step` does not know `r`. It can do only one thing. It
gets an `r` from something that answers the command, and passes it to the
continuation. `interpret` is such an answer.

A Moore step is the pair `(o, i -> s)` with one fixed `i`. `Step` is the same
pair, where the output is a command and the type of the input is chosen by
that command. `Step f` is the polynomial functor of the protocol `f`.

### A program is a state machine (not built)

A program is a function `t -> Step f t`. The state says where the program is.

```haskell
data S
  = AskName
  | ReadName
  | Greet String
  | ReadLine String
  | Reply String String
  | Bye

program :: S -> Step Command S
program AskName           = Step (PutStrLn "What is your name?") (\() -> ReadName)
program ReadName          = Step GetStrLn (\name -> Greet name)
program (Greet name)      = Step (PutStrLn ("Hello, " <> name)) (\() -> ReadLine name)
program (ReadLine name)   = Step GetStrLn (\line -> if line == "quit" then Bye else Reply name line)
program (Reply name line) = Step (PutStrLn (name <> ": " <> line)) (\() -> ReadLine name)
program Bye               = Step Quit absurd
```

- Sequence: each continuation names the next state.
- Data from earlier steps: it rides in the state.
- Branch: the continuation is an ordinary function of the response.
- Loop: a state goes back to an earlier state.
- Halt: `Quit` has no continuation.

The state type does the work that bind does in `IO`. The cost is that the
program counter is written by hand. `Fix` removes that cost in a later phase.

### Wiring diagrams and the outer interface (not built)

A pile of pure Moore machines can have the protocol as its outer interface.

- The pile stays as in Lensy Moore. The inner machines are plain
  `Moore s i o`, tensored and wired with plain lenses. `Step` does not appear
  inside.
- Only the last wiring is new. It takes the outputs of the pile and gives a
  `Step`.

```haskell
wiring :: o -> Step Command i

plug :: Moore s i o -> (o -> Step f i) -> (s -> Step f s)
plug (Lens m) w = \s -> case m s of
  (o, k) -> case w o of
    Step command g -> Step command (\r -> k (g r))
```

`plug` is lens composition where the second lens is dependent. The result is
a program whose state is the state of the full pile. For example, the
Fibonacci machine from the post with real output:

```haskell
plug fibMachine (\n -> Step (PutStrLn (show n)) (\() -> ()))
```

In Poly, a wiring diagram is a map from the tensor of the inner interfaces to
the outer one. The outer one is now the polynomial of the protocol.

Limits:

- One command per step for the full pile. If two machines each want an effect
  in the same step, the outer interface must be a tensor or a sum of
  protocols.
- Inner wires have fixed types. The wiring knows the command, so it can
  convert the response with no catch-all. The inner machines see one plain
  input type.
- The wirings in the post use some values two times. In the linear `Lens`,
  those wires must carry `Ur` values.

### The plan for the program side

1. `Step`.
2. A pure echo program of type `t %1 -> Step Command t`.
3. The closed loop that runs a program against `console`.
4. `main` changed to run it, with `Quit` as a real halt.

Phase 3 has its own copy of `Lens.hs`. After the closed loop exists, the
parts of that copy that phase 3 does not use, such as `moore`, can go.

### Deferred: Fix

```agda
data Fix (A : Type) (B : A → Type) : Type
  roll : (x : A) → (B x → Fix A B) → Fix A B
```

```haskell
data Fix f where
  Roll :: f r -> (r -> Fix f) -> Fix f
```

`Fix Command` is a tree of interactions, and it is the fixed point of
`Step Command`. It hides the state, so a program is nested continuations that
read like a `do` block. Nothing before it depends on it.

### Dragons

- Existential types with linear arrows. Type inference gets weak and
  annotations grow.
- The classes in monoidal-functors do not apply. A protocol has kind
  `Type -> Type`.
- Tensor and sum of protocols need their own GADTs, such as
  `data Sum f g r = L (f r) | R (g r)`.
- Agda computes `Response c` from a value. Haskell can only carry the index.

### History note

The Dialogue IO of Haskell 1.0 had programs of type
`[Response] -> [Request]`. This design is near to that, as a machine and not
a lazy list.

## Files

Each phase of the design is a separate module tree under `src`. A phase
imports nothing from another phase, so some code is repeated. Each phase has
a top module that exports `main` and has a comment with what the phase shows
and what its defect is.

| Phase | Modules | Content |
| --- | --- | --- |
| 1 | `Phase1`, `Phase1.Lens`, `Phase1.World`, `Phase1.Console` | The token is a value. Each effect is a function `World %1 -> (a, World)`. One Moore machine owns the token |
| 2 | `Phase2`, `Phase2.Lens`, `Phase2.World` | Each effect is a Mealy machine on `World`, made with `liftIO`. A program is a Moore machine built by composition. Sections "The design" and "About the token" describe this phase |
| 3 | `Phase3.Lens`, `Phase3.World`, `Phase3.Console` | Command and response. The protocol and the world side are built. The program side is not, so there is no `Phase3` top module and no `main` yet |

`app/Main.hs` selects the phase. Remove the comment marker from one line and
put one on the others.

```haskell
main :: IO ()
main =
  -- Phase1.main
  Phase2.main
```

Run it in the dev shell (`nix develop`) with `cabal run realworld-haskell`.
Phases 1 and 2 are echo programs. They read a line and write it back, and
they give no prompt.

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

Parallel composition of machines that both hold `World` is put aside. In the
command and response design only one machine holds the token, and the pure
machines tensor freely.

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
