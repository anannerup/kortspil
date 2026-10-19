Status: ready-for-agent

# Spec: Navigation between the game and the account area

## Problem Statement

The site has two kinds of pages, and nothing connects them. The **lobby** (and soon the **bord** pages) is a React page at the root. The friends page, the admin pages and the change-password page are server-rendered pages. The only navigation is a row of links in a top bar: Admin, Venner, Skift adgangskode and Log ud. Once you are on the friends or admin page there is no link back to the lobby, and there is nothing that tells you which part of the site you are in. With tables arriving (practice table, ticket 06), a player who goes to the friends page in the middle of a **spil** will have no obvious way back to their **bord**. The site feels like two separate apps.

## Solution

One persistent top bar on every page for signed-in, approved users, with a clear switch between two areas:

- **Spil**, the game world: the lobby and the **bord** you are sitting at.
- **Konto**, the account world: Venner, Admin (admins only) and Skift adgangskode.

The bar always shows which area you are in. "Spil" takes you back to your **bord** if you are sitting at one, otherwise to the lobby. A small marker on "Spil" shows that a **bord** is waiting for you. Leaving the game area never takes you off your seat. Inside the Konto area, a sub-navigation switches between its pages. In the game area, the bar is compact so the table gets the space.

## User Stories

1. As a player, I want a top bar on every page, so that I can always get to any part of the site.
2. As a player, I want the bar to show whether I'm in "Spil" or "Konto", so that I always know where I am.
3. As a player, I want to click "Spil" to get to the lobby, so that I can find or start a game from anywhere.
4. As a player sitting at a **bord**, I want "Spil" to take me back to that **bord** rather than the lobby, so that I don't lose my game.
5. As a player sitting at a **bord**, I want a marker on "Spil" (e.g. "Ved bordet"), so that I remember a game is waiting for me while I'm in Konto.
6. As a player sitting at a **bord**, I want a way to reach the lobby from the **bord** page, so that I can look around without leaving my seat.
7. As a player, I want going to Venner or Admin to keep my seat, so that checking a friend request doesn't cost me my place.
8. As a player, I want "Konto" to open the friends page by default, so that the most used account page is one click away.
9. As a player in the Konto area, I want a sub-navigation (Venner, Skift adgangskode, and Admin if I'm admin) with the current page marked, so that I can move around the account pages.
10. As an admin, I want Admin inside the Konto area, so that it doesn't clutter the game area.
11. As an admin, I want the existing admin sub-navigation (Ventende, Alle brugere) kept under Admin, so that admin pages stay organised.
12. As a non-admin, I want to never see the Admin entry, so that the bar only shows what I can use.
13. As a player, I want the friend-request badge on "Konto" (and on "Venner" inside it), so that I notice requests from the game area.
14. As a player, I want my username and "Log ud" always visible in the bar, so that I know who is logged in and can log out from anywhere.
15. As a player, I want the site name "Kortspil" in the bar to take me to the lobby, so that the usual web convention works.
16. As a player on a **bord** page, I want the bar to be compact, so that the felt and my hand get as much room as possible.
17. As a player, I want the bar to work by click and touch and fit a phone-width screen, so that it works on any device (desktop first).
18. As a player using the browser's back and forward buttons, I want them to move between pages as expected, so that navigation isn't surprising.
19. As a pending or rejected user, I want to see no game or Konto navigation, only the waiting page with "Log ud", so that I'm not shown things I can't use.
20. As a visitor who is not logged in, I want the login and signup pages without the bar, so that those pages stay simple.
21. As a player, I want the bar to look the same on React pages and server-rendered pages, so that it feels like one app.
22. As a player, I want every page to have a way back (to the lobby, to my **bord**, and to the previous level, e.g. from "set password" back to "Alle brugere"), so that I never get stuck and never have to edit the URL by hand.
23. As a player who hits an error or a page that doesn't exist, I want a page with the bar and a link to the lobby, so that even mistakes have a way out.

## Implementation Decisions

- **One shared bar, rendered by the Rails layout.** The bar is part of the server layout on every page, the React pages included (the lobby and the **bord** mount inside the same layout). React does not draw its own copy, which avoids two implementations drifting apart.
- **The area is decided on the server.** Each controller declares whether it belongs to the "spil" area (home/lobby, tables) or the "konto" area (friendships, passwords, admin). The layout reads that declaration to mark the active area and to choose the full or compact bar. The default is "spil".
- **The "Spil" link target.** The user's current seat decides it: if the user sits at a **bord** that is not finished, "Spil" points to that **bord**'s URL and shows the "Ved bordet" marker; otherwise it points to the lobby. This needs one query on the user, along the lines of "my current **bord**". Until ticket 06 merges there are no tables, so the method always returns none, and 06 or 12 fills it in. That keeps this ticket independent of 06.
- **"Konto"** points to the friends page. The Konto sub-navigation is a shared partial rendered at the top of every Konto page. The admin pages keep their own sub-navigation underneath it.
- **The friend-request badge** count is computed once in the layout and shown on both "Konto" and "Venner".
- **Pending, rejected and logged-out users** get no bar. The waiting page shows "Log ud" only, as today.
- **Styling** is plain and neutral, in line with the rest of the UI that isn't designed yet: a bar with two clearly separated tabs and an obvious active state. The compact variant on **bord** pages is a thinner bar, not a hidden one. The bar wraps or collapses sensibly at phone width.
- **Hard rule: no dead ends.** Every page an approved user can reach must render the bar, which includes a one-click way to the lobby. Every sub-page (e.g. an admin user's set-password form) also has a visible link back to its parent page. The 404 and 500 pages get the bar too when the user is signed in and approved, or a plain "Til forsiden" link otherwise.
- **No client-side router is introduced.** Moving between areas is ordinary page navigation. Inside the game area, React may handle transitions between lobby and **bord** later, but that isn't required now.
- **Coordination with ticket 06.** The practice-table work is being built in parallel on its own branch and may touch the layout and add the tables routes. Whichever lands second adapts: the tables controller declares the "spil" area, and "my current **bord**" gets implemented against the real tables.

## Testing Decisions

- **Good tests** assert what the user sees and where links go (rendered links, the active marker, which entries exist per role), not how the layout is built internally.
- **Seam: request tests.** These are the existing seam, the same style as the auth, admin and friends tests. They cover:
  - an approved user sees the bar with Spil/Konto, their username and Log ud on the lobby, friends, password and admin pages
  - the active area is marked correctly on each page
  - the Konto sub-navigation is present on Konto pages, with the current page marked
  - Admin appears only for admins, in both the Konto sub-navigation and access
  - the badge appears on Konto and Venner when there are pending requests
  - pending, rejected and logged-out users see no bar
  - "Spil" points to the lobby when not seated. Once tables exist (06/12), a further test checks that a seated user's "Spil" points to their **bord** and shows the marker.
- **The no-dead-ends guard** is a request test that walks every GET route in the app that an approved admin can reach, filling in fixture records for ids. It asserts that each page renders the bar with a link to the lobby. A new page without a way back then fails the build automatically. Routes that aren't pages, like `/up`, are excluded explicitly.
- **No browser tests.** The behaviour is server-rendered links.

## Out of Scope

- A visual design for the bar and the Konto area. That waits for Anders's design work; only the card style is taken from the design system so far.
- A user menu dropdown or avatars.
- Live updates of the badge or the "Ved bordet" marker without a page load. The badge goes live with ticket 16's notification listener.
- A client-side router or single-page navigation across areas.
- The mobile app shell.

## Further Notes

- Terms come from GLOSSARY.md: **bord**, **spil**. "Konto" and "Spil" as area names are new UI words. Add them to the glossary if Anders keeps them.
- This replaces the current flat top bar (Admin, Venner, Skift adgangskode, Log ud).
- The test seam is request tests only, including the route-walking no-dead-ends guard. "Must always be able to navigate back" is Anders's explicit requirement.
