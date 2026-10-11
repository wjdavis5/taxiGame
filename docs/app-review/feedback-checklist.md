# Feedback checklist — physical device (issue #273)

Run once on a physical iPhone before shipping, with the app built from the
release branch. Every named event must show its own cue, and every cue must
follow the in-app Sound and Vibration toggles (Settings).

How to run: play an endless shift with Sound on and Vibration on and hit each
event in order. Then repeat the four marked rows with Sound off, and the four
marked rows with Vibration off, to prove the gates.

| # | Event | How to trigger | Cue to confirm | Sound off | Vibration off | Done |
|---|-------|----------------|----------------|-----------|---------------|------|
| 1 | Bank | Take a fare, press BANK on the bank-or-push panel | Banked jingle, medium tick, banked summary panel | ✓ | ✓ | ☐ |
| 2 | Push | Take a fare, press PUSH ON (or let the window close) | Rising two-tone, light tick, `PUSH ON ×N` pop at the cab | ✓ | ✓ | ☐ |
| 3 | Chain break | Ride a fare until its timer crosses zero with the chain above 1× | Falling two-tone, heavy tick, red `CHAIN BROKEN ×N LOST` pop | ✓ | ✓ | ☐ |
| 4 | Late delivery | Ride a fare until its timer hits LATE, then deliver | Red `LATE` settlement pop, late-delivery tick, dropoff chime | ✓ | ✓ | ☐ |
| 5 | Scrape | Graze a traffic car or cone | Scrape sound, sparks, marker naming the vehicle | ✓ | — | ☐ |
| 6 | Daily settlement | Finish (bank or wreck) a Daily Shift | Amber "TODAY'S DAILY IS IN" banner and its own medium tick | ✓ | ✓ | ☐ |
| 7 | Pause | Tap the pause button in the HUD | Button click and light tick before the menu opens | ✓ | ✓ | ☐ |
| 8 | Summary actions | On the run summary, press DRIVE AGAIN, RACE YOUR GHOST, and MAIN MENU | Button click and light tick on each | ✓ | ✓ | ☐ |
| 9 | Fare settlement line | Deliver any fare | HUD line under the scoring row names status, value × multiplier, any chain bonus, and the at-risk total; it clears after a few seconds | — | — | ☐ |
| 10 | Level payout truth | Complete a tutorial level | Coin pops fly only as the wallet is credited; the completion panel's `+N Coins` equals the wallet delta | — | — | ☐ |

Short-phone check (also on device: iPhone SE-class 320 pt width):

- The bank-or-push panel and the settlement line are both up after a dropoff:
  nothing overlaps the cab, neither overflows, both stay one line.
- The run summary's title, payout, and buttons stay one line each.
