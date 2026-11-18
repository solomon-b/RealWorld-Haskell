# Notes: linear machines as an alternative to monadic IO

Last update: 2026-11-17.

The repo is a workshop for a blog post. The post replaces monadic IO with
linear Moore and Mealy machines and shows effectful programs in that
paradigm. The aim is an alternative with power similar to monads.

## Phase plan

Each phase is a separate module tree that compiles and runs alone. The phases
record how the design changes from one step to the next.

| Phase | Subject                                                                                                                                                    | Status      |
|-------|------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------|
| 1     | The token is a value. Each effect is a function `World %1 -> (a, World)`. One Moore machine owns the token                                                 | Built       |
| 2     | Each effect is a Mealy machine on `World`, made with `liftIO`. A program is a Moore machine built by composition                                           | Built       |
| 3     | Command and response. The world is a Mealy machine that answers a protocol. A program is pure, a function from a state to a `Step`                         | Built       |
| 4     | Wiring diagrams. A pile of pure Moore machines, joined with the plain `tensor` from Lensy Moore. `plug` gives the pile the protocol as its outer interface | Not started |
| 5     | `Tree`. The fixed point of `Step`, which hides the state of a program                                                                                      | Not started |
| 6     | `Tensor` and `both`. The parallel product on protocols, so that two programs can each give a command in the same step                                      | Not started |

The order of phases 5 and 6 is not confirmed. Phase 6 does not depend on
phase 5.

What each later phase needs:

- Phase 4 needs `Step` and plain Moore machines. Phase 3 has both.
- Phase 5 needs only `Step`.
- Phase 6 needs `Step` and `Program`. It lifts the main limit of phase 4, one
  command per step for the full pile.

Open decision for phase 4: the lens type of the pure machines.

- The linear `Lens` everywhere gives one lens type and one set of
  combinators. Each value that a machine uses two times or drops must be in
  `Ur`, so `counter` is a `Moore (Ur Int) () (Ur Int)`.
- A plain lens for the pile reads as in the post. It gives two lens types,
  and two copies of `compose` and `tensor`.
- A linear function can be used where a plain function is expected. So a
  pile of linear machines can still go into `plug` and give a plain
  `Program`.
- A lens with a multiplicity parameter, `s %m -> (a, b %m -> t)`, could give
  both. It is not checked.

## The design (phase 2)

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

## The command and response design (phases 3 to 6)

This is the current direction. It is the next step after the Lensy Moore post
and cofree-bot. The world is one machine that owns the token. The program is
pure code. A closed loop runs the program against the world.

Status: the protocol, the world side, `Step`, a pure echo program, and the
closed loop are built, and phase 3 runs. `plug` and the wiring of a pile of
machines are not built, and the claims about them are by hand.

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

### Step (built)

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
arguments and not in the result type.

The program side is not linear. A program is pure, and its state is ordinary
data, so `Step` has plain arrows. Only the closed loop is linear. It holds
the token and the program state together, as `(World, Ur t)`.

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

### A program is a state machine (built)

A program is a function `t -> Step f t`. The state says where the program is.
`Phase3.echo` is a small program of this form, with a `quit` line that gives
the `Quit` command. The larger example below is not in the repo.

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
program counter is written by hand. `Tree` removes that cost in phase 5.

### Phase 4. Wiring diagrams and the outer interface (not built)

A pile of pure Moore machines can have the protocol as its outer interface.

The pile uses the plain `tensor` on machines, as in the post. It does not
need `both`. `both` pairs two things that already speak a protocol, and in
this phase no inner machine does.

```haskell
tensor :: Moore s i o -> Moore t i' o' -> Moore (s, t) (i, i') (o, o')
```

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
  protocols. Phase 6 has the tensor.
- Inner wires have fixed types. The wiring knows the command, so it can
  convert the response with no catch-all. The inner machines see one plain
  input type.
- The wirings in the post use some values two times. In the linear `Lens`,
  those wires must carry `Ur` values.

### The closed loop (built)

```haskell
close ::
  (forall r. Mealy World (Ur (f r)) (Ur r)) ->
  Program f t ->
  Moore (World, Ur t) () ()

main = run Reading (close console echo)
```

Each step of `close` takes one command from the program, gives it to the
world, and gives the response to the program. It is `annihilate` for this
shape, with the program on the Moore side.

`Quit` runs `exitSuccess`, and the program ends with exit code 0. End of file
on stdin still ends the program with an exception.

The phase 3 copy of `Lens.hs` has no `moore`, `lmap`, or `rmap`, because
phase 3 does not use them. It keeps `compose` for the wiring work.

### The general trick: a protocol is a dependent polynomial

This is from Reed. A type `f :: Type -> Type` encodes a dependent polynomial.
`f r` is the type of the positions whose direction type is `r`. `Command r`
is one such `f`.

`Step f t` is the polynomial as a functor. It is a position and a function
from its direction. Reed calls this the ΣΠ interpretation.

A protocol with one response type gives the plain Moore machine again.

```haskell
data Mono o i r where
  Mono :: o -> Mono o i i
```

`Program (Mono o i) t` is `t -> (o, i -> t)`, which is `Moore t i o`. So
`Program` is a Moore machine with a dependent interface, and no conversion to
`Moore` is needed to pair it with the world. The program is the Moore side.
`console` is the Mealy side. `close` is `annihilate` for those two types.

### Phases 5 and 6

Neither phase is started. Each needs a decision to start.

**Phase 5. Tree.** Reed's type, with the response type hidden at each node.

```haskell
data Tree f where
  Tree :: f r -> (r -> Tree f) -> Tree f
```

In Agda this is the `Fix` from the same conversation.

```agda
data Fix (A : Type) (B : A → Type) : Type
  roll : (x : A) → (B x → Fix A B) → Fix A B
```

`Tree f` is the fixed point of `Step f`. `Step` is one layer, and `Tree` is
the layers nested with the state hidden. A program is then nested
continuations that read like a `do` block.

```haskell
Tree GetStrLn (\name -> Tree (PutStrLn ("hello " ++ name)) (\() -> Tree Quit absurd))
```

The type in the chat was `data Moore cmd r = Moore (cmd r) (r -> Moore cmd r)`.
That has `r` as a parameter, so every node has the same response type. The
example needs a hidden `r`, as above. Nothing before phase 5 depends on it.

**An idea for phase 5: `do` notation with no monad.** This is by hand and is
not compiled.

The `QualifiedDo` extension lets a `do` block take its `>>=` and `>>` from a
module that the code names. It does not ask for a `Monad` instance, and the
two functions can have any types. For `Tree`, the bind is the constructor.

```haskell
module Tree.Do where

(>>=) :: f r -> (r -> Tree f) -> Tree f
(>>=) = Tree

(>>) :: f r -> Tree f -> Tree f
c >> k = Tree c (\_ -> k)
```

A program is then a real `do` block.

```haskell
greet :: Tree Command
greet = Tree.Do.do
  PutStrLn "What is your name?"
  name <- GetStrLn
  PutStrLn ("hello " ++ name)
  stop

stop :: Tree Command
stop = Tree Quit absurd
```

- Each statement is a bare command. The last line is a `Tree`.
- A loop is ordinary recursion, with the name of the program as the last
  line.
- The point for the post: the `do` block needs no monad, and its bind is the
  `Tree` constructor. The notation was never tied to the class.
- The limit: the left side of `<-` is a single command. A `Tree` has no
  result, so the result of another tree cannot be bound there. A tree with a
  result type, `Tree f a`, is the free monad.

An example of the limit. A helper prints a question and gives back the
answer, and a program uses it two times.

```haskell
ask :: String -> Tree Command
ask question = Tree.Do.do
  PutStrLn question
  GetStrLn                             -- error 1

greet :: Tree Command
greet = Tree.Do.do
  name <- ask "What is your name?"     -- error 2
  age  <- ask "How old are you?"
  PutStrLn (name ++ " is " ++ age)
  stop
```

- Error 1: the last line of a block must be a `Tree Command`, and `GetStrLn`
  is a command. `ask` wants to say that it ends with a `String`, and
  `Tree Command` has no place for that. A tree only ends at `Quit`.
- Error 2: the left side of the bind must be one command, `f r`, and
  `ask "..."` is a tree.

So this is not possible: write a piece of a program that produces a value,
give it a name, and use it in the middle of another program. Every tree is a
whole program to the end.

A helper can take the rest of the program as an argument. That works, but the
calls to it are nested lambdas outside the `do` notation.

```haskell
ask :: String -> (String -> Tree Command) -> Tree Command
ask question continue = Tree.Do.do
  PutStrLn question
  answer <- GetStrLn
  continue answer

greet :: Tree Command
greet =
  ask "What is your name?" $ \name ->
    ask "How old are you?" $ \age -> Tree.Do.do
      PutStrLn (name ++ " is " ++ age)
      stop
```

There are two ways to get `name <- ask "..."`, and each one is a monad.

- A result type on the tree, `Tree f a`. That is the free monad.
- A bind that takes helpers of type `(r -> Tree f) -> Tree f` on its left
  side. That is the continuation monad, without the class.

A quasiquoter can give the same notation. It would turn `x <- c; rest` into
`Tree c (\x -> rest)`. It needs a Haskell parser for the expressions in the
statements, such as `haskell-src-meta`, which is one more dependency. It is
worth it only for syntax that a `do` block cannot give.

**Phase 6. Tensor and both.** The parallel product of Poly, on protocols.

```haskell
data Tensor f g r where
  Tensor :: f a -> g b -> Tensor f g (a, b)
```

A command of the tensor is one command from each protocol. Its response is
both responses. Two pure programs then compose in parallel. This is by hand.

```haskell
both :: Program f s -> Program g t -> Program (Tensor f g) (s, t)
both p q (s, t) = case (p s, q t) of
  (Step c k, Step d l) -> Step (Tensor c d) (\(a, b) -> (k a, l b))
```

- This is the parallel composition that was not possible when both machines
  held `World`. Programs are pure, so nothing blocks it.
- It removes the limit of one command per step for a pile of machines. The
  outer interface can be a tensor of protocols.
- The world has one token, so it must answer a `Tensor` command in some
  order, left and then right. That choice is in one function on the world
  side, and no program sees it.

### Dragons

- Existential types with linear arrows. Type inference gets weak and
  annotations grow.
- The classes in monoidal-functors do not apply. A protocol has kind
  `Type -> Type`.
- Tensor and sum of protocols need their own GADTs. `Tensor` is in the plan
  for phase 6. A sum would be `data Sum f g r = L (f r) | R (g r)`.
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

| Phase | Modules                                                                     | Content                                                                                                                                                                           |
|-------|-----------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1     | `Phase1`, `Phase1.Lens`, `Phase1.World`, `Phase1.Console`                   | The token is a value. Each effect is a function `World %1 -> (a, World)`. One Moore machine owns the token                                                                        |
| 2     | `Phase2`, `Phase2.Lens`, `Phase2.World`                                     | Each effect is a Mealy machine on `World`, made with `liftIO`. A program is a Moore machine built by composition. Sections "The design" and "About the token" describe this phase |
| 3     | `Phase3`, `Phase3.Lens`, `Phase3.World`, `Phase3.Console`, `Phase3.Program` | Command and response. The world is a Mealy machine that answers a protocol. A program is pure, and `close` runs it against the world                                              |

`app/Main.hs` selects the phase. Remove the comment marker from one line and
put one on the others.

```haskell
main :: IO ()
main =
  -- Phase1.main
  -- Phase2.main
  Phase3.main
```

Run it in the dev shell (`nix develop`) with `cabal run realworld-haskell`.
All three phases are echo programs. They read a line and write it back, and
they give no prompt. Phase 3 stops when the line is `quit`.

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
