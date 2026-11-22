# Delegation: crew leaders and captains

*Describes the code on `main` at v0.5.0 (dd5b8db).*

## The short answer

Yes, they're different, and the difference is rank and scope.

- A **group** is a **crew** (the game's own word): villagers working together on one job. Its **leader** is the crew leader. Every crew has one. You give a crew its steps, and it carries them out as one unit.
- A **captain** is a crew leader you have promoted. Captaincy changes what the leader and their crew can do on their own. It is a rank, and a captain can also be given a **post**, which is a place and a purpose they run without further orders.

| | Crew leader | Captain (rank) | Captain with a post |
|---|---|---|---|
| Who | Leader of any crew | A crew leader you promoted | A captain given a mandate |
| Runs | One job, up to 8 steps | Their own crew | A place and purpose, with its people |
| Acts on its own | No. Waits for steps | Only what its crew was told | Yes: staffs jobs, builds within limits, reacts to threats |
| Crew after work ends | Crew disbands | Crew stays | Members join the post |
| Can be given a mandate | Only the leader, unless already a captain | Yes, and brings their crew | Yes, changes the post |

## Vocabulary

- **Villager**: any person you can order.
- **Crew**: a group working on one job. Made when you order several people together, or when a crew gets a plan.
- **Crew leader**: the crew member you address. The first member becomes leader. If the leader dies or leaves, the longest-serving member takes over.
- **Captain**: a crew leader with the captain rank. Shown as "Captain Hal".
- **Post**: what a captain runs once given a **mandate**. Each post has one captain, a radius, a target size, and a list of its people.
- **Mandate**: the place and purpose of a post (see below).

The title "Captain Hal" in an order addresses that person. It does not promote them. Only the `promote` step, or a mandate, makes a captain.

## Crew leaders

What you can do with a crew leader and their crew:

- **Give steps.** Up to 8 steps per crew: gather, build, craft, smelt, research, arm, mount, scout, guard, attack, follow, hold, recall, and more.
- **Use the crew as one group.** A crew moves and works together. Looking at a member and talking addresses the crew. Pressing Tab reaches the leader alone.
- **Move people between crews.** Members can be shifted to another crew without restarting its plan.
- **Dismiss.** Releases the addressed individual, or disbands the whole crew.
- **Promote.** `promote` (or "make Hal a captain") makes the leader a captain. Their crew becomes theirs, outside any post.
- **Give a mandate.** A plain crew leader can be given a mandate. Only the leader goes, and their crew stays behind. Only a captain brings their crew.

What a crew leader cannot do:

- Act without steps. A crew with no work ends when its steps run out, unless its leader is a captain.
- Keep a post running.

## Captains

A captain is a crew leader with the captain rank. Captaincy adds:

- **The crew stays together.** When a captain's crew finishes its steps, it is not disbanded.
- **The crew comes along.** A captain given a mandate brings their crew.
- **A title that means something.** "Captain Hal" addresses them, and other people can be named by "Captain" in orders.
- **Limits.** `reserve`, `forbid`, `allow` and `posture` are settings for a captain. They can be given alone, or after a mandate in the same order. They cannot be mixed with other steps.

Captaincy alone does not make anyone autonomous. Autonomy comes from a post.

## Posts and mandates

A mandate gives a captain a place (the spot you name, the village, or the spot the captain stands on), a purpose, and a list of what they may build. From `scripts/data/defs.gd`:

| Mandate | Runs | Radius | Target size | May build |
|---|---|---|---|---|
| `village` | "run the village" | 152 m | everyone free | hut, farm, stockpile, quarry, armory, stable, palisade and gates, stone wall and gate, watch post, tower |
| `farming` | "run the farms" | 70 m | 8 | farm, stockpile, hut, watch post |
| `industry` | "run the mines and works" | 90 m (210 m near home) | 10 | mine, quarry, smelter, armory, university, stockpile, watch post |
| `garrison` | "hold a garrison" | 45 m | 8 | armory, palisade and gates, stone wall and gate, tower, watch post |
| `army` | "raise an army" | 35 m | 10 | nothing |

A "count" in the order sets the target size. The default is the table's size.

Once a post exists it runs itself, roughly once a second:

- **Staffing.** The village post takes everyone free and staffs the other posts. Without a village post, a post takes the nearest idle adults until it reaches its target.
- **Orders to the post.** "Captain Hal, send two scouts east" is carried out by as many of the post's people as the order needs, and the captain keeps working. Free people and post jobs go first, then people already under direct orders. Orders with no count default to a sensible number, such as the post's fighters for an attack.
- **Jobs.** It decides who gathers, builds and crafts, within its mandate.
- **Building.** It picks sites inside its radius, from its list of what it may build. It respects `forbid` and `allow`, and leaves the `reserve` in store.
- **Threats.** It reports attacks once, and it reacts. Its `posture` decides whether it holds or falls back when outnumbered. In a raid, builders and crafters put their tools down, and paid-for work resumes afterwards.
- **Succession.** If the captain dies or leaves, the longest-serving non-child member takes over. If nobody is left, the post closes.

## What captains won't do

These are checked by the tests, so they're deliberate:

- Start an attack, or found a new post, on their own.
- Undo a direct order. Anyone you have ordered directly is left to that order until it finishes.
- Build outside their mandate, or build what you have `forbid`den.
- Spend into the `reserve`.
- Find an unseen deposit. A captain only knows ground and resources their side has seen.

## Giving orders

| You want to | Say or do |
|---|---|
| Talk to one villager | Look at them, or select them and press Enter |
| Talk to a crew | Look at a member, or select the crew |
| Talk to a captain's post | Look at the captain, or name them |
| Promote a crew leader | "promote", "make Hal a captain" |
| Put a captain in charge | "Hal, run the village", "Hal, run the farms" |
| Order a captain's people | "Captain Hal, send two scouts east" |
| Set limits | "keep 100 wood back", "don't build farms", "stand your ground" |
| Release a person or disband a crew | "dismiss" |
| See everyone | `/p` lists captains first, then crews |

Terra turns plain language into steps, and the game validates them before anything runs. Slash commands and the local parser skip the model for simple orders.

## When the chain of command breaks

- **A direct order overrides a captain.** Giving a villager an order removes them from their post's jobs, and the captain won't touch them until the order is done.
- **A dead or departed leader is replaced.** The longest-serving member takes over. A captain's heir becomes captain.
- **Nobody left.** A post with no one to run it closes, and its people are free.

## Related

- `scripts/sim/captains.gd`: what a captain decides each second.
- `scripts/sim/captain_works.gd`: what a captain builds.
- `scripts/sim/captain_watch.gd`: what a captain does under threat.
- `scripts/sim/match_work.gd`: crews, posts, and succession.
- `scripts/sim/match.gd`: orders to crews and captains (`give_mandate`, `_post_detail`).
- `scripts/data/defs.gd`: mandates and the order schema.
