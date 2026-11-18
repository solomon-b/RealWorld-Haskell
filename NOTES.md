# Notes: linear machines as an alternative to monadic IO

Last update: 2026-11-17.

The repo is a workshop for a blog post. The post replaces monadic IO with
linear Moore and Mealy machines and shows effectful programs in that
paradigm. The aim is an alternative with power similar to monads.

## Phase plan

Each phase is a separate module tree under `src` that compiles and runs
alone. A phase imports nothing from another phase, so some code is repeated.
The phases record how the design changes from one step to the next.

| Phase | Subject                                                                 | Status      |
|-------|-------------------------------------------------------------------------|-------------|
| 1     | The token is a value. Effects are functions on it                       | Built       |
| 2     | Effects are Mealy machines on the token                                 | Built       |
| 3     | Command and response. The world answers a protocol. Programs are pure   | Built       |
| 4     | Wiring diagrams. A pile of pure machines with the protocol on the outside | Built     |
| 5     | `Tree`. The state of a program is hidden                                | Not started |
| 6     | `Tensor`, and `tensor` on programs. Two programs each give a command in the same step | Not started |

The order of phases 5 and 6 is not confirmed. Phase 6 does not depend on
phase 5.

`app/Main.hs` selects the phase to run. It has one line for each phase.
Remove the comment marker from one line and put one on the others.

```haskell
main :: IO ()
main = Phase1.main

-- main = Phase2.main
-- main = Phase3.main
-- main = Phase4.main
```

Each line is a full definition, so that ormolu keeps the lines in place.

Run it in the dev shell (`nix develop`) with `cabal run realworld-haskell`.

## Naming

The project has five views of the same things: machines, lenses, Poly,
effects in Haskell, and pictures. The rule for a name depends on the kind of
thing.

1. Types get the machine name. `Moore`, `Mealy`, `Program`, `Step`. The
   reader's model of the project is machines, so the nouns are machine nouns.
2. Combinators get the name of the operation in Poly, as a plain word. If a
   function is a composition, a tensor, or a known map, it has that name. Its
   doc comment gives the Poly definition.
3. The edge to `IO` keeps the names of Haskell. `liftIO`, `interpret`,
   `World`. That is where a reader arrives from ordinary Haskell.
4. Examples get names from their domain. `echo`, `fib`, `console`, `outer`,
   `feedback`.

## Background: the token

These facts about GHC apply to every phase.

- `RealWorld` is a type with no values. It is only a tag. It marks which
  thread of state a token belongs to, as the `s` in `ST s` does.
- `State# RealWorld` is the token. `State#` is a primitive type with no
  constructor, and a token has zero size at runtime.
- `IO` is a state monad that threads the token.
  `newtype IO a = IO (State# RealWorld -> (# State# RealWorld, a #))`.
  `State#` is not a monad. It is the state that the monad carries.
- The token exists only for sequencing. Each effect takes a token and returns
  a new one, so each effect depends on the effect before it.
- A token can be made from nothing with `realWorld#` or `runRW#`. Thus a token
  is not proof of ownership. The discipline must come from the code around
  it.

## Phase 1. The token is a value

One Moore machine holds the token in its state. The observation and the
transition call effects, and each effect is a function on the token.

Modules: `Phase1`, `Phase1.Lens`, `Phase1.World`, `Phase1.Console`.

### `Lens`

```haskell
newtype Lens s t a b = Lens {runLens :: s %1 -> (a, b %1 -> t)}
```

A linear lens. It takes a value `s` and uses it one time. It gives a view
`a`, and an update function that takes a `b` and gives a `t`. The caller must
use the update function one time.

An ordinary lens has two separate functions, `view :: s -> a` and
`set :: s -> b -> t`, and both take `s`. A linear lens cannot have both,
because `s` can be used only one time. So the two are joined in one function.

In Poly this is a map `monomial s t ⇒ monomial a b`.

### `Moore`

```haskell
type Moore s i o = Lens s s o i
```

A Moore machine with state `s`, input `i`, and output `o`. From the state
alone, it gives an output, and a function from an input to the next state.
The output does not depend on the input of the same step.

In Poly this is `monomial S S ⇒ monomial O I`.

### `World`

```haskell
data World = World (State# RealWorld)
```

A box around the token. `State# RealWorld` is an unlifted type, so it cannot
be a parameter of `Lens` or a part of a pair. The box makes it an ordinary
type. It adds no meaning. The module does not export the constructor, so no
outside code can open the box.

### `Ur`

```haskell
data Ur a where
  Ur :: a -> Ur a
```

"Unrestricted". Linear code can use the value inside an `Ur` any number of
times. A line of text that was read from stdin is ordinary data, so it comes
back in an `Ur`.

### `perform`

```haskell
perform :: IO a -> World %1 -> (Ur a, World)
```

Runs one `IO` action against the token. It gives the result and the next
token. It only removes the `IO` newtype. It has the one unsafe cast of the
repo, which tells GHC that the token is used one time. GHC checks linearity
in all other code.

### `getLine` and `putStrLn`

```haskell
getLine  :: World %1 -> (Ur String, World)
putStrLn :: String -> World %1 -> World
```

The effects of this phase. Each one is `perform` on a function from base.

### `run`

```haskell
run :: (World %1 -> s) -> Moore s () () -> IO ()
```

The driver. It gets the token from `IO`, makes the first state from it, and
steps the machine in a loop. The machine must have no input and no output.
The loop has no halt path. It stops only when an effect throws an exception,
for example at end of file.

### The program: `echo`

```haskell
echo :: Moore (Ur Int, World) () ()
echo = Lens $ \(Ur n, world) -> case Console.getLine world of
  (Ur line, world') ->
    ( (),
      \() -> (Ur (n + 1), Console.putStrLn (show n <> ": " <> line) world')
    )
```

The state is a line counter and the token. The observation reads a line. The
transition writes it with its number.

### Defect

An effect has the type `World %1 -> (a, World)`. That is the state monad of
`IO` with another name. The machine holds the token, but it does not manage
the state. The code in the machine passes the token by hand.

## Phase 2. Effects are Mealy machines

An effect is no longer a function on the token. It is a machine whose state
is the token. A program is a Moore machine on the same state, and it is built
by composition. This design comes from a conversation with Reed Mullanix.

Modules: `Phase2`, `Phase2.Lens`, `Phase2.World`.

`Lens`, `Moore`, `World`, `Ur`, and `perform` are as in phase 1. `perform` is
now private to `Phase2.World`.

### `Mealy`

```haskell
type Mealy s i o = Lens (s, i) s o ()
```

A Mealy machine with state `s`, input `i`, and output `o`. It takes the state
and the input together, and gives an output and the next state. The output
can depend on the input of the same step. That is the difference from Moore.

In Poly this is `monomial (S × I) S ⇒ monomial O ⊤`. In Agda the output map
and the next state map are separate functions. Here they are one function,
because the pair can be used only one time.

### `mealy` and `runMealy`

```haskell
mealy    :: (s %1 -> i %1 -> (o, s)) -> Mealy s i o
runMealy :: Mealy s i o -> s %1 -> i %1 -> (o, s)
```

They convert between a Mealy machine and its step function. The step
function is the shape that is easy to write and to call. `mealy` hides the
`\() -> s'` that every Mealy machine has as its update.

### `lmap` and `rmap`

```haskell
lmap :: (i' %1 -> i) -> Mealy s i o -> Mealy s i' o
rmap :: (o %1 -> o') -> Mealy s i o -> Mealy s i o'
```

`lmap` changes the input of a Mealy machine, and `rmap` changes the output.
The phase needs them only to convert between `()` and `Ur ()`.

### `compose`

```haskell
compose :: Lens s t a b -> Lens a b c d -> Lens s t c d
```

Lens composition. The second lens goes inside the view of the first. For
machines, the second lens is a wiring. It gives the first machine a new
outside interface.

### `liftIO`

```haskell
liftIO :: (i -> IO o) -> Mealy World (Ur i) (Ur o)
```

Makes a machine from a function in `IO`. The machine does the effect one time
for each input. It is exported, so any module can add an effect. It is the
one way to add an effect.

A `Mealy World i o` has the same shape as `i -> IO o`, uncurried.

### `getLine` and `putStrLn`

```haskell
getLine  :: Mealy World (Ur ()) (Ur String)
putStrLn :: Mealy World (Ur String) (Ur ())
```

The same effects as in phase 1, now as machines. Each is one call to
`liftIO`.

### `runThen`

```haskell
runThen :: Mealy s () o -> Mealy s i () -> Moore s i o
```

Runs one machine, and then runs a second machine from the state that the
first one returned. The first gives the observation of the result. The second
gives the transition.

It started as glue with the name `moore`, and then `fromMealys`. It is a
standard construction. The reading in Poly is checked in Agda, in the
cofree-coffee/poly repo, in `src/Poly/Machines/FromMealys.agda`. That file is
not committed there yet.

1. The Moore interface is a composite, `O y^I ≅ O y ◁ y^I`. A Moore step is
   an output step and then an input step.
2. `Mealy S ⊤ O` is the same data as a map `S y^S ⇒ O y`, which is a function
   `S → O × S`.
3. `Mealy S I ⊤` is the same data as a map `S y^S ⇒ y^I`, which is a function
   `S → I → S`.
4. With `δ : S y^S ⇒ S y^S ◁ S y^S`, the comultiplication of the store
   comonoid, `runThen f g = δ ⨟ (f ◁ g)`, followed by the isomorphism of
   part 1.

All four parts hold with no change, and every proof is `refl`.

- The construction works for any two interfaces. Maps `S y^S ⇒ Q` and
  `S y^S ⇒ R` give a map `S y^S ⇒ Q ◁ R` by the same formula.
- It uses nothing specific to the store. It works for any comonoid for `◁`.
- The Poly book has the case where both maps are the same,
  `Run_n(φ) = δ^(n) ⨟ φ^{◁n}`, in the subsection "Running dynamical systems"
  of the chapter "Polynomial comonoids and retrofunctors". `runThen` is
  `Run_2` with two different systems. The name comes from there.

So phase 2 already has a form of sequencing from `◁`, before any protocol
exists.

Not verified:

- The match between the Agda function and the Haskell one is by reading. The
  Haskell version is linear and the Agda version is not.
- The section of the book is from its TeX source. By a count of the chapters
  it is 7.1.5, and that number is not confirmed against the PDF.
- The search of the book for a name did not cover its third part.

In an ordinary Moore machine the readout is `S → O`. Here the readout returns
a state, because it uses the state one time.

The name `moore` is kept free for a constructor from plain functions, to
match `mealy`.

### `run`

```haskell
run :: Moore World () () -> IO ()
```

The driver, as in phase 1. The state of the machine is the token alone.

### The program: `console`, `feedback`, and `echo`

```haskell
console :: Moore World (Ur String) (Ur String)
console =
  runThen
    (lmap (\() -> Ur ()) World.getLine)
    (rmap (\(Ur ()) -> ()) World.putStrLn)

feedback :: Lens a a () ()
feedback = Lens $ \a -> ((), \() -> a)

echo :: Moore World () ()
echo = console `compose` feedback
```

`console` is the console as one Moore machine. Its output is a line that it
read, and its input is a line to write. `feedback` is a wiring that sends the
output of a machine to its input. `echo` is the two composed. No code in the
program touches the token.

### Defects

- A program is a machine on `World`. To tensor two such programs needs two
  tokens. Ideas for that were a `dup` lens that forks the world, and smaller
  tokens such as `Stdin` and `Stdout`. Both are put aside.
- The driver has no halt path.
- `console` must convert between `()` and `Ur ()`.

## Phase 3. Command and response

The world is one machine that owns the token and answers the commands of a
protocol. A program is pure code. A closed loop runs the program against the
world. This is the next step after the Lensy Moore post and cofree-bot.

Modules: `Phase3`, `Phase3.Lens`, `Phase3.World`, `Phase3.Console`,
`Phase3.Program`.

`Lens`, `Moore`, `Mealy`, `mealy`, `runMealy`, `compose`, `World`, `Ur`, and
`liftIO` are as in phase 2. This phase has no `runThen`, `lmap`, `rmap`,
`getLine`, or `putStrLn`.

### Where the design comes from

The start was `annihilate` from the Poly Agda repo.

```agda
annihilate
  : ∀ {S T A B : Set}
  → Moore S A B
  → Mealy T B A
  → monomial S S ⊗ monomial T T ⇒ 𝕐
```

One machine is a Moore machine and the other is a Mealy machine. The output
of each is the input of the other. The result is a closed system with no
input and no output. The pairing must be Moore against Mealy. The Moore
output does not depend on the current input, and that breaks the cycle.

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

- If the world is the Moore machine, it shows the response to the previous
  command. Then `Response` must be one ordinary type, and the program has a
  catch-all case for a response that does not fit its command.
- If the response type depends on the command, the world cannot answer until
  it has seen the command. So the world is the Mealy machine. The program
  gives the command first, so the program is the Moore side.

This phase uses the second design.

### `Command`

```haskell
data Command r where
  PutStrLn :: String -> Command ()
  GetStrLn :: Command String
  Quit :: Command Void
```

The console protocol. The type parameter `r` is the type of the response to
the command. Haskell cannot write a function from a value to a type, so
Reed's `Response` function is this parameter. Each constructor states its
own response type.

`Quit` has the response type `Void`, which has no values. So no response can
come back, and nothing can come after `Quit`. The halt path is inside the
protocol.

An alternative makes `Response` visible, as a type family over a `Tag` kind.
It needs `DataKinds` and `TypeFamilies`. The two forms carry the same
information.

### A protocol is a dependent polynomial

This is from Reed. A type `f :: Type -> Type`, such as `Command`, encodes a
dependent polynomial. `f r` is the type of the positions whose direction type
is `r`. A position is a command, and its direction is its response.

### `interpret`

```haskell
interpret :: Command r -> IO r
```

Does one command in `IO`. Its type is exact. For each command it returns the
response type of that command. `interpret Quit` is `exitSuccess`, which has
the type `IO Void`. All monadic `IO` of a program is in this one function.

### `console`

```haskell
console :: Mealy World (Ur (Command r)) (Ur r)
console = liftIO interpret
```

The world side of the protocol, as a Mealy machine on the token. It takes a
command and gives the response to that command. It is polymorphic in `r`, so
it is one machine for each response type. It needed no new machinery.

### `Step`

```haskell
data Step f t where
  Step :: f r -> (r -> t) -> Step f t
```

One step of a program that speaks the protocol `f`. It holds a command, and a
function from the response to the next state `t`.

The reason for it: one step must say which command to do and how to continue.
A plain pair `(Command r, r -> t)` fails as the result of a program, because
`r` would be one type for the whole program. One state wants `GetStrLn`,
where `r` is `String`, and another wants `PutStrLn`, where `r` is `()`.
`Step` lets each step choose its own `r`, and hides it. `r` is in both
arguments and not in the result type.

```haskell
Step GetStrLn        (\line -> Printing line)   -- r is String
Step (PutStrLn line) (\()   -> Reading)         -- r is ()
Step Quit            absurd                     -- r is Void
```

These three values have the same type. The compiler checks each one when it
is built. The function must accept the response type of its command.

Code that opens a `Step` does not know `r`. It can do only one thing. It gets
an `r` from something that answers the command, and passes it to the
function.

`Step` is not a machine and not a lens. It is the result of one run of a
machine. It is to `Program` what the pair `(o, i -> s)` is to `Moore`. As a
functor in `t`, `Step f` is the polynomial of the protocol `f`. Reed calls
this the ΣΠ interpretation.

`Step` has plain arrows. A program is pure, and its state is ordinary data,
so the program side is not linear.

### `Program`

```haskell
type Program f t = t -> Step f t
```

A program with state `t` that speaks the protocol `f`. The state says where
the program is. From the state alone, the program gives a command, and a
function from the response to the next state.

A `Program` is a Moore machine with a dependent interface.

```haskell
Moore s i o   ≅   s -> (o, i -> s)
Program f t   =   t -> Step f t
```

The output is a command, and the type of the input is chosen by that command.
So no conversion to `Moore` is needed to pair a program with the world. A
protocol with one response type gives the plain Moore machine again.

```haskell
data Mono o i r where
  Mono :: o -> Mono o i i
```

`Program (Mono o i) t` is `t -> (o, i -> t)`, which is `Moore t i o`.

As a lens, `Program f t` is a dependent lens from `t y^t` to the polynomial
of the protocol. In general, a function `s -> Step f t` is a dependent lens
from `s y^t` to the protocol. Only the target can be dependent in this
encoding. The source is always a monomial.

How a program is made from states:

- Sequence: each function names the next state.
- Data from earlier steps: it rides in the state.
- Branch: the function is an ordinary function of the response.
- Loop: a state goes back to an earlier state.
- Halt: `Quit` has no next state.

The state type does the work that bind does in `IO`.

### `annihilate`

```haskell
annihilate ::
  Program f t ->
  (forall r. Mealy World (Ur (f r)) (Ur r)) ->
  Moore (World, Ur t) () ()
```

Runs a program against a world machine. Each step takes one command from the
program, gives it to the world, and gives the response to the program. The
result has no input and no output. Its state is the token and the state of
the program.

It is the `annihilate` of the Agda repo for these two types, and it takes its
arguments in the same order, the Moore side and then the Mealy side. The
program is the Moore side and the world is the Mealy side. It is the only
linear code on the program side.

### `run`

```haskell
run :: t -> Moore (World, Ur t) () () -> IO ()
```

The driver. It takes the start state of the program. The loop stops when an
effect throws an exception. `Quit` uses that. It runs `exitSuccess`, and the
program ends with exit code 0.

### The program: `echo`

```haskell
data Echo
  = Reading
  | Printing String
  | Stopping

echo :: Program Command Echo
echo = \case
  Reading ->
    Step GetStrLn (\line -> if line == "quit" then Stopping else Printing line)
  Printing line -> Step (PutStrLn line) (\() -> Reading)
  Stopping -> Step Quit absurd

main = run Reading (annihilate echo console)
```

It reads a line and writes it back. It stops when the line is `quit`.

### Defects

- The state of a program is its program counter, written by hand. Each line
  of the program is a constructor, and each live variable is a field.
- A program gives one command for each step.
- End of file on stdin still ends the program with an exception.

### History note

The Dialogue IO of Haskell 1.0 had programs of type
`[Response] -> [Request]`. This design is near to that, as a machine and not
a lazy list.

## Phase 4. Wiring diagrams

The program is a pile of pure Moore machines from the Lensy Moore post. The
machines are joined with a tensor and wired with a plain lens. One last
wiring gives the pile the console protocol as its outer interface. The result
is a `Program` as in phase 3.

Modules: `Phase4`, `Phase4.Lens`, `Phase4.Wiring`, `Phase4.World`,
`Phase4.Console`, `Phase4.Program`.

`World`, `Ur`, `liftIO`, `Command`, `interpret`, `console`, `Step`,
`Program`, `annihilate`, and `run` are as in phase 3. Their types now name
the multiplicity `'One` where they use a lens.

### `Lens`, with a multiplicity

```haskell
newtype Lens (m :: Multiplicity) s t a b = Lens {runLens :: s %m -> (a, b %m -> t)}
```

One lens type for linear lenses and for plain lenses.

The problem that it solves: the token needs a linear lens, and the machines
of the post cannot be linear. `counter` shows its state and also uses it for
the next state, which is two uses. So the phase needs both kinds of lens.

In GHC every function arrow has a multiplicity. It says how many times the
function can use its argument.

```haskell
a %1 -> b      -- is  a %'One  -> b    exactly one time
a -> b         -- is  a %'Many -> b    any number of times
```

So `->` and `%1 ->` are one type constructor with a different setting, and
the setting can be a type variable. `Lens` has it as its first parameter.

- `Lens 'One s t a b` is the linear lens of phases 1 to 3. The machines that
  hold the token have this multiplicity.
- `Lens 'Many s t a b` is a plain lens. The pure machines have this
  multiplicity, so they can use a value two times or drop it, with no `Ur`.

Two lenses must have the same `m` to be composed or tensored. A `'Many`
machine cannot be joined directly to a `'One` machine. This phase does not
need that. The pile is all `'Many`, and `into` and `annihilate` are where the
pure side meets the world.

The first version of this phase had two lens types, the linear one and `Lens`
from the `microlens` library. In GHC, a linear function can go where a plain
function is expected only with an explicit lambda around it.

### `Moore` and `Mealy`

```haskell
type Moore m s i o = Lens m s s o i
type Mealy m s i o = Lens m (s, i) s o ()
```

The aliases of phase 2, with the multiplicity passed through. `fib` is a
`Moore 'Many`, and `console` is a `Mealy 'One`.

### `lens`

```haskell
lens :: (s -> a) -> (s -> b -> t) -> Lens 'Many s t a b
```

Makes a plain lens from a view function and an update function. It is the
`lens` of the post, so the machines of the post are written as they are
there. It exists only at `'Many`, because the two functions both take `s`.

### `compose`

```haskell
compose :: Lens m s t a b -> Lens m a b c d -> Lens m s t c d
```

Composition of maps in Poly, as in phase 2, now for every multiplicity. GHC
checks a function for every `m` under the strict reading. It must be correct
at `'One`, so its body must use each value one time. Such a body is also
correct at `'Many`.

### `tensor`

```haskell
tensor :: Lens m s t a b -> Lens m s' t' a' b' -> Lens m (s, s') (t, t') (a, a') (b, b')
```

Runs two lenses side by side. For machines, the state, the input, and the
output of the result are pairs. Each machine keeps its own state, and both
step one time for each step of the pair.

This is the parallel product ⊗ of Poly, on maps. The pairs in the type are ⊗
on the monomial interfaces. It is one function for pure machines and for
machines on the token.

### The pile: `plus`, `delay`, `plusDelay`, `fibWiring`, and `fib`

```haskell
plus  :: Moore 'Many Int (Int, Int) Int
plus  = lens id (\_ (x, y) -> x + y)

delay :: Moore 'Many Int Int Int
delay = lens id (\_ y -> y)

plusDelay :: Moore 'Many (Int, Int) ((Int, Int), Int) (Int, Int)
plusDelay = plus `tensor` delay

fibWiring :: Lens 'Many (Int, Int) ((Int, Int), Int) Int ()

fib :: Moore 'Many (Int, Int) () Int
fib = plusDelay `compose` fibWiring
```

This is the pile of the post. The bodies of the machines are the same as
there. Two things differ: the types name `'Many`, and `fib` uses `compose`
where the post has `.`, because these lenses are not in the functor form.

`plus` sets its state to the sum of its two inputs. `delay` sets its state to
its input, so it shows the input of the step before. `fibWiring` is an inner
wiring. It sends both outputs to `plus`, sends the output of `plus` to
`delay`, and gives the output of `delay` to the outside. `fib` is the pile
composed with that wiring. Its output is the Fibonacci sequence.

### The outer wiring: `outer`

```haskell
outer :: Int -> Step Command ()
outer n
  | n > 1000 = Step Quit absurd
  | otherwise = Step (PutStrLn (show n)) (\() -> ())
```

A wiring from the interface of `fib` to the console protocol. It makes two
choices. From the output of the pile, it chooses one command. From the
response to that command, it makes the input of the pile.

It has the same job as `fibWiring`, with a command on the outside. As a lens,
it is a dependent lens from `Int y^()` to the protocol.

### `into`

```haskell
into :: Moore 'Many s i o -> (o -> Step f i) -> Program f s
into machine wiring s = case runLens machine s of
  (o, next) -> case wiring o of
    Step command continue -> Step command (\response -> next (continue response))
```

Composes a machine with an outer wiring. The result is a program whose state
is the state of the full pile. It is composition in Poly, `Syˢ ⇒ Oyᴵ ⇒ p`,
where the second map is a dependent lens to the polynomial `p` of the
protocol. It is the same operation as `compose`. It has its own function
because `compose` cannot take a dependent lens.

In Poly, a wiring diagram is a map from the tensor of the inner interfaces to
the outer one. The outer one is now the polynomial of the protocol.

### The program

```haskell
main = run (1, 0) (annihilate (fib `into` outer) console)
```

It writes the Fibonacci numbers from 0 to 987, one for each line, and stops
with exit code 0. It takes no input.

### Defects

- One command for each step, for the full pile. The outer wiring must choose
  one command from all the outputs. If two machines each want an effect in
  the same step, the outer interface must be a tensor or a sum of protocols.
  Phase 6 has the tensor.
- Inner wires have fixed types. The outer wiring knows the command, so it
  can convert the response with no catch-all. The inner machines see one
  plain input type.

An example that shows the first defect is not built. A latch machine reads
numbers from stdin and writes the largest so far. Each number needs a
`GetStrLn` and then a `PutStrLn`, which is two steps. But the tensor steps
every machine on every step, so on the second step the latch gets an input
with no new number. The fix is an input type such as `Maybe Int`, or a small
controller machine in the pile.

## Phase 5. Tree (not started)

Everything in this phase is by hand and is not compiled.

### `Tree`

```haskell
data Tree f where
  Tree :: f r -> (r -> Tree f) -> Tree f
```

A full program as a tree of interactions. Each node is a command, and a
function from its response to the rest of the program.

`Tree f` is the fixed point of `Step f`. A `Step f t` is one layer that ends
in a state `t`. A `Tree f` is the layers nested, with no state type. So
`Tree` removes the main defect of phase 3. The program counter is no longer
written by hand.

```haskell
Tree GetStrLn (\name -> Tree (PutStrLn ("hello " ++ name)) (\() -> Tree Quit absurd))
```

In Agda this is Reed's `Fix`.

```agda
data Fix (A : Type) (B : A → Type) : Type
  roll : (x : A) → (B x → Fix A B) → Fix A B
```

The type in the chat was `data Moore cmd r = Moore (cmd r) (r -> Moore cmd r)`.
That has `r` as a parameter, so every node has the same response type. The
example needs a hidden `r`, as above.

### `do` notation with no monad

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

A quasiquoter can give the same notation. It would turn `x <- c; rest` into
`Tree c (\x -> rest)`. It needs a Haskell parser for the expressions in the
statements, such as `haskell-src-meta`, which is one more dependency. It is
worth it only for syntax that a `do` block cannot give.

### The limit: a tree has no result

The left side of `<-` is a single command. The result of another tree cannot
be bound there. In this example, a helper prints a question and gives back
the answer, and a program uses it two times.

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

## Phase 6. Tensor (not started)

Everything in this phase is by hand and is not compiled.

### `Tensor`

```haskell
data Tensor f g r where
  Tensor :: f a -> g b -> Tensor f g (a, b)
```

The parallel product of Poly, on protocols. A command of the tensor is one
command from each protocol. Its response is both responses. This is from
Reed.

`Tensor` is ⊗ on objects. It takes two protocols and gives a protocol. Phase
4 has no such type, because all its interfaces are monomials, and the tensor
of two monomials is a monomial, `o y^i ⊗ o' y^i' = (o, o') y^(i, i')`. There
⊗ on objects is only pairs in a signature. A protocol is not a monomial, so
the tensored object needs a name.

### `tensor`, on programs

```haskell
tensor :: Program f s -> Program g t -> Program (Tensor f g) (s, t)
tensor p q (s, t) = case (p s, q t) of
  (Step c k, Step d l) -> Step (Tensor c d) (\(a, b) -> (k a, l b))
```

Runs two programs in parallel as one program. Each gives its own command in
the same step.

This is ⊗ on maps, and so is the `tensor` of phase 4. They are the same
operation. The phase 4 one is the case where both interfaces are monomials.
An earlier name for this one was `both`.

```haskell
tensor :: Lens m s t a b -> Lens m s' t' a' b' -> Lens m (s, s') (t, t') (a, a') (b, b')   -- phase 4
tensor :: Program f s    -> Program g t        -> Program (Tensor f g) (s, t)              -- phase 6
```

- This is the parallel composition that was not possible in phase 2, when
  both machines held `World`. Programs are pure, so nothing blocks it.
- It removes the limit of one command for each step.
- The world has one token, so it must answer a `Tensor` command in some
  order, left and then right. That choice is in one function on the world
  side, and no program sees it.

## Dragons

Problems to expect with dependent protocols in Haskell.

- Existential types with linear arrows. Type inference gets weak and
  annotations grow. The pure program side avoids most of this.
- The classes in monoidal-functors do not apply. A protocol has kind
  `Type -> Type`.
- Tensor and sum of protocols need their own types. A sum would be
  `data Sum f g r = L (f r) | R (g r)`.
- Agda computes `Response c` from a value. Haskell can only carry the index.

## Ideas put aside

- A `dup` lens, `Lens World World (World, World) (World, World)`, that forks
  the world for a tensor of two machines on `World`. Effects are in order
  along each side only.
- Smaller tokens, one for each protocol, with a lens
  `Lens World World (Stdin, Stdout) (Stdin, Stdout)`. It is `dup` with types
  that say which machine touches what.
- A `Category` instance for the phase 4 `Lens`, so that `.` and `>>>` take
  the place of `compose`. It works in a scratch test. The class wants two
  parameters, so an object must be a pair of types, which is a monomial.

  ```haskell
  newtype Lens (m :: Multiplicity) (p :: (Type, Type)) (q :: (Type, Type))
    = Lens {runLens :: Fst p %m -> (Fst q, Snd q %m -> Snd p)}

  type Moore m s i o = Lens m '(s, s) '(o, i)
  ```

  `Fst` and `Snd` are type families that take a pair apart. They let `id`
  exist for every object. The category is the full subcategory of Poly on
  monomials. The order of `.` is the reverse of the post, so
  `fib = fibWiring . plusDelay`, or `plusDelay >>> fibWiring`. The costs are
  `TypeFamilies`, promoted pairs in the types of wirings, and weaker type
  inference. `into` would stay a separate function, because a protocol is
  not a monomial. The decision was to keep `compose`.
- An output of `Either r o` to say that a machine has finished.
- The fixed point of a machine that can halt with a result is a free monad.
- monoidal-functors has classes for the tensor of plain machines. Version
  0.3.0.0 has a `laws` library, but nixpkgs has 0.2.3.0.

## History

Two earlier versions are in `git stash`.

- "spike v1" has the design of phase 1, and also a `Borrow` machine that
  passes the token on its wires, monoidal-functors instances, and `andThen`.
- "spike v2" has GHC's `RealWorld` as the machine state with no token, and
  `unsafePerformIO` on each effect. GHC gives no guarantee for its order of
  effects.

No test covers the library. The test suite has one placeholder property.

## References

- cofree-bot, `machines-coalgebras`:
  https://github.com/cofree-coffee/cofree-bot/tree/main/machines-coalgebras
- Lensy Moore: https://blog.cofree.coffee/2024-07-02-lensy-moore/
- monoidal-functors: https://github.com/solomon-b/monoidal-functors/

## Ancillary todos

Small items that are not part of a phase.

- Confirm the order of phases 5 and 6.
- Handle end of file on stdin. All phases end with an exception there.
- Add a prompt to the echo programs, so that the wait for input is visible.
- Add tests. The test suite has one placeholder property.
