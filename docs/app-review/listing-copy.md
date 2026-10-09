# Cab Hustle — App Store listing copy

Paste-ready copy for the App Store Connect listing, written after the
Guideline 4.3(a) rejection (2026-10-08, issue #212): every field should lead
with what makes the game its own, so a reviewer never has to guess.

The listing is maintained in App Store Connect — the release pipeline never
overwrites it (`skip_metadata` in `taxi_game/fastlane/Fastfile`) — so these
fields are applied by hand on the version page.

## Name (30 max)

`Cab Hustle`

## Subtitle (30 max)

`Daily & Endless Taxi Shifts` — 27 characters.

## Promotional text (170 max)

`One thumb, one shift. Race today's ghost on the Daily Shift, then push your
luck on an Endless Shift — bank the fare chain at a dropoff or risk it for
more.` — under the 170-character cap (check the counter before pasting).

## Keywords (100 max, comma-separated)

`taxi,arcade,daily,ghost,endless,shift,bank,traffic,one-thumb,offline,records,garage`
— 83 characters.

## Description

Cab Hustle is a one-thumb arcade taxi game — and a different shift every time
you pick it up.

DAILY SHIFT
Everyone drives the same course each day. Race the ghost of your best
attempt, then live with the once-a-day result. Yesterday's course is gone
tomorrow.

ENDLESS SHIFT
Three crashes and the shift is over. At every dropoff, bank the fare chain
or push on for more — the third crash forfeits whatever is unbanked.
Near-misses pay, so precision is what scores.

GARAGE & RECORDS
Earn coins, unlock vehicles with real handling differences, and chase your
own records, lifetime stats, and achievements.

ALL ON YOUR PHONE
No account, no network, no ads, no in-app purchases, no tracking. Progress
is saved on-device.

Drive smart. Bank often. See you out there.

## Screenshots (6.9″ iPhone, 1320×2868, no alpha)

The first two frames should show the Daily Shift (ghost race) and a
bank-or-push moment — the two things no other taxi game shows. Capture with
the pipeline in `CLAUDE.md` (`tool/screenshot_entry.dart`), then strip the
alpha channel with `tools/strip_alpha.swift`.

## What's New (for the resubmitted version)

`taxi_game/fastlane/whats_new.txt` — the submit lane writes it onto the
version before submitting.
