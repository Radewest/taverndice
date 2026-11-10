# Tavern Dice changelog

## v0.2.3 (2026-11-10)
- Mumpits: a pair of 5s is now your choice. Keep both, or throw one back in the cup to roll again (both score 100). A button under the hint switches between them.
- If your last two dice are 5-5, keeping both is the default, so it's **hot dice** instead of rolling one die.
- The regulars weigh both options too.

## v0.2.2 (2026-11-10)
- First release published automatically to CurseForge. No gameplay changes since v0.2.1.

## v0.2.1 (2026-11-10)
- **Find players with Tavern Dice.** The new-game panel lists *Nearby with Tavern Dice*: players within about 250 yards, plus anyone in your group or guild, each with an Invite button (greyed out if they're already at a table). Click *Look around* to check again.
- Targeting a player quietly checks whether they have the add-on, and their tooltip says "Tavern Dice: up for a game" if they do.
- `/dice findme` hides you (and stops you looking) if you'd rather not be found.
- The tjommie button just says "Invite my tjommie"; their name is in the tooltip.
- Window is a little taller to make room.

## v0.2.0 (2026-11-10)
- **Play a friend, near or far.** Invite from the new-game panel, with `/dice invite Name`, or by right-clicking any player and choosing *Invite to Tavern Dice*. They get an invitation pop-up with your rules. Works across realms and factions with Battle.net friends, otherwise same realm and faction.
- **Tjommie integration:** "Invite my tjommie" (or `/dice tjommie`) invites whoever you're linked with in Tjommie.
- In a group, each player's add-on checks the other's server /roll dice; a roll that doesn't match is refused.
- **Table talk:** when your friend is beside you, your character /says "Hot dice!", cheers and gloats when you win, and sighs or grunts at a Farkle. Quiet when you're far apart. Setting: auto / always / off.
- **New look:** wooden table, green felt, leather ledger, storybook title font, new logo and icon. Dice stay centred however many are left.
- New-game panel redesigned in two columns (regulars / a friend) with house rules below; no more text spilling out of buttons.
- Fixed the first line of the tavern log disappearing at the start of a game.
- Tavern log reads properly for you ("You win", "You pass 10,000").

## v0.1.1 (2026-11-10)
- New ruleset **Mumpits** (pick it under Rules in the new-game panel): you can never bank less than 400 in a turn, and two 5s make 100 with one of the 5s going back in the cup to be rolled again.
- Dice are a little smaller so all six fit on the felt.
- New game button moved to the foot of the ledger, clear of the close button. The new-game panel has a "Back to the game" button while a game is running.
- Fixed "You says" / "You stares" in the tavern log.

## v0.1.0 (2026-11-09)
- First version: play 10,000 (Farkle / Dix Mille) solo against up to three tavern regulars.
- Three bot styles: Old Barnaby (cautious), Mira Ashvale (balanced), Grizzle Sparkfuse (reckless).
- Standard scoring: 1 = 100, 5 = 50, three of a kind = face x 100 (three 1s = 1,000), each extra die doubles it, straight 1,500, three pairs 1,000. Hot dice, Farkle, opening score and a final round once someone passes the target.
- Game options: play to 2,000 / 5,000 / 10,000; opening minimum none / 350 / 500 / 1,000; pace brisk / relaxed / slow.
- Optional server dice: each throw is one real /roll (0-46655 read as six dice), with our roll lines hidden from your chat. Falls back to local dice if the roll doesn't come back.
- Dice table window with tumbling dice, set-aside tray, ledger, tavern log, FARKLE / HOT DICE pop-ups and sounds.
- Your record at the table (/dice stats), minimap button, bug log (/dice bugs).
