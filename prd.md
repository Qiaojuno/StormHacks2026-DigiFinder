# PRD: Assistive Grocery Navigation (StormHacks '26)

Oct 3, 2026 · @Ethan · Status: Draft v2

> **Product context only:** who this is for, why it matters, what it must do and how we judge it. Every technical and behavioral detail (thresholds, spoken wording, architecture) lives in `implementation_plan.md`, which wins if the two disagree.

## Overview

We are building a voice-first iPhone app that guides a blind or low-vision shopper from the store entrance to the right product in their hand, one list item at a time. It works like a **digital guide dog**. The phone hangs on a lanyard at chest height, and the user opens the app with Siri and says what they need. The phone camera then reads the store around them: entrances, aisle signs, obstacles, shelves and the item they point at.

**Problem.** Grocery stores are one of the hardest everyday places to navigate without sight. Layouts change between stores, products look alike by touch (a can of chickpeas vs a can of black beans), and asking staff for help means waiting and losing independence. General-purpose scene describers say what is in front of you, but they do not walk you to a goal.

**Why grocery first.** Grocery stores share a predictable structure the app can lean on: one main entrance, numbered aisles with overhead category signs, shelves at reachable heights, and a list-driven trip. That structure lets us turn the trip into a reliable loop: find entrance, find sign, find aisle, find shelf, confirm item, repeat.

**Why a digital guide dog.** Most blind people use a white cane, which only finds what it touches at ground level. Guide dogs also warn about things at body and head height. But most people can't get one because of long training programs, waitlists, cost, housing rules and allergies. The app brings that part of a guide dog's job to the phone people already own, used alongside the cane.

**Product promise.** "Tell me what you need, and I'll get your hand on it."

## Users and goals

The primary user is a blind or low-vision adult who shops independently with a white cane and no guide dog, and who already uses VoiceOver and Siri daily. Guide dog handlers are not the v1 target: the dog already steers around obstacles, so our alerts would repeat or conflict with its guidance. Cane users have no warning for moving carts or anything above waist height, which is where the app adds the most.

| Persona | Situation | What they need from us |
| --- | --- | --- |
| Maya, 34, totally blind, cane user | Weekly shop at her local store, knows the rough layout | Exact item confirmation (brand, size, flavour) without asking staff |
| Daniel, 61, low vision (late-onset) | Can see large shapes, not shelf labels | Sign and label reading, gentle step-by-step pacing |
| Priya, 22, cane user, new to the city | Visiting an unfamiliar store | Entrance finding and aisle-level wayfinding in a new layout |

**Goals**

- Get the user from near the store entrance to the correct product in hand, with no sighted help.
- Confirm the item matches the goal before it goes in the cart.
- Keep the user safe while moving: warn of carts, people, displays and anything at waist-to-head height, and announce stairs.
- Keep hands free: voice and the volume buttons control everything, and the phone vibrates only for danger.
- Work without internet: the whole shopping trip runs on the phone; only the AI extras need a connection.

**Non-goals (v1)**

- Outdoor routing to the storefront: existing navigation apps already get users near the entrance safely; indoors is the unmet need.
- Floor-level hazards (single steps, curbs, low boxes, wet floors, drop-offs): that is the cane's job.
- Scanning, payment and bagging: staff handle these once the app brings the user to checkout.
- Integrations with store inventory or indoor maps.
- Replacing the white cane as the primary mobility aid, or supporting guide dog handlers.
- Deli counter, bakery or other staffed-counter ordering.
- Requiring earbuds: everything is designed for the phone speaker (earbuds work if the user prefers them).

## User flow

The trip loops once per list item until the list is done:

Siri launch → say the item or list → *(if outside)* find the entrance → find an aisle sign → walk to the aisle → walk the aisle → point at the shelf → confirm the item → grab it → next item

The entrance step is skipped when the user starts inside. Danger alerts and stairs announcements can interrupt any walking step. The detailed flow is in the implementation plan.

## Functional requirements

P0 = hackathon demo; P1 = usable in a real weekly shop; P2 = after the hackathon. Priorities match the build order in the implementation plan.

| ID | Phase | Requirement | Priority |
| --- | --- | --- | --- |
| L1 | Launch | "Hey Siri, open [app]" starts the app hands-free, camera on, no screen taps | P0 |
| L2 | Launch | User says one item or a whole list; the app reads the list back to confirm | P0 |
| L3 | Launch | App knows whether the user is outside or already inside (asks, or tells from the camera) | P1 |
| L4 | Launch | In a noisy store, favour list items and brand names; if a request isn't understood, say so, mention the noise, and ask the user to speak up | P0 |
| L5 | Launch | Volume up stops the app talking and opens the mic; volume down ends the recording | P0 |
| L6 | Launch | Change of mind and additions by voice ("actually peanut butter", "also milk") | P0 |
| E1 | Entrance | Find the store entrance and guide the user to it with clock-face directions. Online, AI picks out the entrance; offline, the app guides to the nearest door and says it can't confirm it's the entrance | P1 |
| E2 | Entrance | Announce the entrance 6–8 m before reaching it | P1 |
| E3 | Entrance | Announce stairs with direction, rough step count and distance, by voice only; handrails on request (online) | P1 |
| E4 | Entrance | Name automatic or revolving doors and cart corrals at the entrance (online) | P1 |
| S1 | Signage | Read overhead aisle signs (aisle number + categories) | P0 |
| S2 | Signage | Map the goal item to an aisle category (e.g. "peanut butter" → "Spreads, Jams") | P0 |
| S3 | Signage | If no sign is in view, ask the user to step back; if still none, scan slowly or walk to the end of the aisle and use item groupings | P0 |
| S4 | Signage | Find perimeter zones with no aisle signs (produce, dairy, bakery, frozen) from what's on the shelves | P0 |
| N1 | Navigation | Direct the user toward the target aisle using the sign position | P0 |
| N2 | Navigation | Warn of obstacles at waist-to-head height in the walking path (carts, people, displays) with vibration and voice, and say which way to steer | P0 |
| N3 | Navigation | Once in the right aisle, prompt the user to walk slowly while the app keeps reading | P0 |
| N4 | Navigation | At the right aisle, say which way to turn, in clock-face directions | P0 |
| N5 | Navigation | Say "Stop" when the user reaches the target aisle, since they can't judge aisle length | P0 |
| N6 | Navigation | If orientation is lost after a detour, ask the user to walk ahead and look for the next end-of-aisle sign | P0 |
| P1 | Pick | Ask the user to point at the shelf; detect the hand and the product under the fingertip | P0 |
| P2 | Pick | Confirm whether the pointed product matches the goal (brand, product, size, variant); if a close variant is there, name both: "This is X; there's also a Y option" | P0 |
| P3 | Pick | If not a match, guide the hand up, down, left or right toward the match | P0 |
| P4 | Pick | Once matched, restate the goal and tell the user to grab it | P0 |
| P5 | Pick | Verify the grabbed item; if wrong, ask the user to put it back and try again | P0 |
| P6 | Pick | On a correct grab, confirm aloud and tick the item off the list | P0 |
| P7 | Pick | Read price and best-before date on request (online) | P1 |
| P8 | Pick | Flag the user's stated allergens or dietary filters found on the label | P2 |
| C1 | Loop | After each item, move on to the next list item | P0 |
| C2 | Loop | Order the remaining list by aisle once aisles have been seen, to cut backtracking | P2 |
| C3 | Loop | "Bring me to checkout" guides the user to the checkout; staff scan the items and take payment | P0 |
| H1 | Help | "Find staff" guides the user to the nearest help desk or customer service sign | P0 |
| A1 | Ask | Free-form questions about what's in front of the user ("Is this gluten free?"), answered by AI when online | P1 |
| W1 | Around | "What's around?" gives one short answer of up to 5 nearby things, then returns to the task | P1 |

## Voice and haptic design

The app speaks less than a sighted guide would and has one vibration pattern: if the phone vibrates, there is danger in the user's path.

**Voice rules**

- One instruction at a time, under 8 words where possible.
- Clock-face directions for heading ("Aisle 6, 9 o'clock"), metres or steps for distance, and up, down, left or right for the hand.
- Danger alerts name the thing and the way out: "Cart ahead, steer left."
- Never talk over VoiceOver.
- Every user action gets a short spoken reply; environmental events have to earn one.
- The user can interrupt any time by pressing volume up and speaking.

**Haptics: danger only**

- 2–3 strong, short vibrations, then the spoken alert. Danger cuts in even mid-conversation, and afterward the app asks the user to say that again.
- Nothing else vibrates. Stairs are spoken only, since the cane is still in hand, and so are item matches, wrong grabs and "Stop" at the aisle. A vibration never needs decoding.

**Hands and audio**

- The phone hangs on a lanyard at chest height, so both hands stay free for the cane and the shelf.
- Audio plays on the phone speaker by default. The speaker is public and can be drowned out, so danger is vibration first and voice second.
- Volume up = talk, volume down = done talking. The screen is ignored while walking.

## Online extras (Gemini)

The whole shopping trip works with no internet. When online, Gemini adds two things:

- **Ask:** free-form questions about what's in front of the user, such as "Is this gluten free?", "How much is this?" or "Is there a handrail?"
- **Entrance finding:** picks out the store entrance from a photo, including automatic or revolving doors and cart corrals.

## Research basis

| Study requirement (team research board) | Design rule in this app |
| --- | --- |
| Hands free; phone on the chest for stability and haptic contact | Lanyard at chest height; all control by voice and the volume buttons; no screen taps while walking |
| Multimodal, since loud environments hurt audio-only navigation | Every danger alert is vibration first, then voice. Nothing else vibrates |
| Low interruption; interrupt only when information becomes actionable | Speak only when it matters: in the walking path, close enough to act on, new or getting worse |
| Prioritise obstacles relevant to immediate movement | Only obstacles in the walking path alert while walking |
| Alert distance depends on the object and the action needed | Alerts are timed by time to contact, so a cart rolling toward you warns earlier than a box you're walking toward |
| Turn-by-turn at critical moments, not constant instructions | Cues only at decision points (aisle turn, shelf, end of aisle) |
| Constant haptics caused overload; few patterns to remember | One vibration pattern, used only for danger |
| Focus mode vs exploratory mode; exhaustive but filterable | Focus is the only mode; "What's around?" gives the fuller picture on request |
| User control of information density | "What's around?", "repeat", "quieter", "more detail" |
| Different ways of understanding space | Clock-face directions; metres or steps in settings; adjustable speech rate |
| Entrance notice 6–8 m before; stairs need distance, direction, handrails | Entrance announced at 6–8 m; stairs with direction, rough step count and distance; handrails through Ask |
| Supplemental to cane | Adds waist-to-head and moving-object warnings; the cane stays primary for the ground |
| Every user action needs feedback; not every environmental event does | Short spoken reply to every command; changes the app makes on its own stay silent |

## Safety and privacy

- The app supplements the white cane and says so at first launch.
- When it isn't sure (dark aisle, blurry view, no sign found), it says so plainly and offers to find staff.
- It never calls an item "safe". Dietary and allergen answers are read as written, then "Check with staff to confirm."
- Camera frames are processed on the phone and discarded; no video is stored. A photo leaves the phone only for an online question or entrance finding.

## Success metrics

- Task success: share of list items reached and correctly picked with no sighted help (target 80% in testing).
- Wrong-item rate: items added to the cart that don't match the goal (target under 5%).
- Time per item, entrance to hand, compared with the user's usual method.
- Safety in testing: no missed carts, people or head-height obstacles in the walking path, and every staircase going up announced.

## Hackathon scope and demo

The demo runs one item end to end, live, starting inside the store: launch by Siri, find the aisle sign, dodge one obstacle, point at a shelf of look-alike products, get corrected once, then grab the right one.

- [ ] Build a mock aisle: a printed overhead sign and a shelf of 4–6 similar products (e.g. canned beans). Make sure the demo products are in the app's offline product list.
- [ ] 2-minute pitch with a blindfolded live run

## Open questions

- Can we test with a blind or low-vision user before demo day, or through a local group such as CNIB?
- Should a remote sighted helper ("call a friend") be a fallback later?

## Licences

- Ultralytics YOLO is AGPL-3.0: fine for an open-source hackathon build; a commercial product would need their enterprise licence.
- Product data comes from Open Food Facts (ODbL) and USDA, credited in the app.

## Sources

- [Indoor Navigation for People With Visual Impairment in Canada: Edge A-Eye co-design study (JMIR Rehabilitation, 2026)](https://rehab.jmir.org/2026/1/e81347)
- [Survey of navigation app use by blind users (Taylor & Francis)](https://www.tandfonline.com/doi/full/10.1080/17483107.2025.2544942)
