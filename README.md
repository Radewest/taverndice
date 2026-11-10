# Tavern Dice (WoW Forever)

Pull up a chair and play 10,000, the old tavern dice game also known as Farkle, Dix Mille, Zilch or Greed. Roll six dice, set aside the ones that score, then push your luck or bank your points. Roll nothing that scores and it's a Farkle: the turn's points are gone. First past 10,000 starts the final round.

Play solo against up to three tavern regulars, or invite a friend, whether they're beside you or across the world. Works with Tjommie: one click invites your tjommie.

## Install
Copy the `TavernDice` folder to `World of Warcraft\_classic_beta_\Interface\AddOns\` (or install from CurseForge).

## Scoring
| Dice | Points |
|---|---|
| Each 1 | 100 |
| Each 5 | 50 |
| Three of a kind | face x 100 (three 1s = 1,000) |
| Four / five / six of a kind | double / quadruple / x8 the three-of-a-kind score |
| Straight 1-2-3-4-5-6 | 1,500 |
| Three pairs | 1,000 |

Score with all six dice and you get **hot dice**: pick them all up and keep rolling.

**Mumpets** house rules: bank at least 400 every turn, two 5s can be "made a 1" (one 5 goes back in the cup), the straight is worth 3,000, and when you're one number short of a straight you can chase it with the spare die (miss and you lose the turn plus 500).

## Commands
| Command | What it does |
|---|---|
| `/dice` | Open or close the dice table |
| `/dice new` | Start a new game with your current settings |
| `/dice invite [name]` | Invite a friend (or your target) |
| `/dice tjommie` | Invite your tjommie (needs Tjommie) |
| `/dice leave` | Leave a game with a friend |
| `/dice findme` | Let nearby players with Tavern Dice find you (on/off) |
| `/dice server` / `/dice local` | Real `/roll` dice from the server, or quiet local dice |
| `/dice stats` | Your record at the table |
| `/dice minimap` | Show or hide the minimap button |
| `/dice reset` | Put the window back in the middle |
| `/dice bugs` | Show the bug log to copy and send to the developer |

Server dice make a real `/roll 0-46655` for each throw, which people near you (or your group) can see. Your own chat hides those lines.
