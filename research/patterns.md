# Cross-app design language

What the studied apps agree on, written as rules Native can check a screen against. "Convergent" means
every app that has the surface does it this way; "split" means winners disagree and it's a real choice.
Sources are the per-app notes (`ai-assistants/*`, `dev-work/*`, `companion/*`). Evidence is from stills
and a few videos, so motion rules are thinner than layout rules.

## 1. Hierarchy and accent

1. **The accent is spent, not sprinkled.** Claude uses its coral on the logo and the send button only;
   Perplexity's teal is the voice button, "New" pill and selected checks; ChatGPT's purple only marks
   Upgrade. Primary CTAs are black (light) / white (dark) pills; toggles fall back to the system tint.
   Rule: the accent appears on at most (a) the primary action, (b) things that need the user, (c) the
   selected/active mark. Never on decoration, headers or icons at rest. *(Convergent.)*
2. **Neutrals carry the screen.** Warm greys (Claude, Perplexity) or cool greys (Grok, v0), never both.
   Status color is reserved for state: green additions and success, red destructive and failure.
3. **One display moment per screen.** Big type is for empty/home greetings and section titles ("Today",
   "Tasks"); conversations use body size everywhere and let weight carry structure (bold lead-ins).
4. **Content is unbubbled, the user is bubbled.** Every AI app renders the assistant as full-width body
   text and the user as a right-aligned soft grey bubble. Tool and work rows sit in between, quieter than
   both. *(Convergent.)*
5. **Chrome floats.** Headers are circular glass/blur buttons over content that scrolls underneath;
   the composer floats at the bottom; search often moves to the bottom too (Claude, ChatGPT, v0, Grok).

## 2. Density and rows

1. **A row is one line of meaning plus at most one line of context.** Title in primary; secondary line
   (project, time, branch, preview) in tertiary, often right-aligned or after a dot separator.
2. **Work rows are a single line**: kind icon, human verb phrase, chevron (v0, Claude Code preview,
   Factory). Commands, paths and output are one tap deeper. Groups of reads fold into one summary.
3. **Settings rows show their value** ("Subscription: Free", "Appearance: System", "Permissions: Read &
   write") so the list doubles as a status page; toggles carry a one- to three-line consequence and say
   when they are forced on by another setting (Claude Capabilities).
4. **Lists are grouped by what the user is deciding**: time buckets for "what happened" (Spark, ChatGPT
   history), Pinned / Active for "what am I working on" (Orca), mode chips for "what kind of run"
   (Perplexity history).
5. **Unread is a dot in the gutter**, not a bold avalanche (Spark, Factory). Counts are neutral chips.

## 3. Typography

1. One family for UI. Claude alone sets responses in a serif; everyone else stays in one sans with a
   mono for code, commands, file names and (Perplexity) timestamps. *(Split: serif is Claude's brand.)*
2. Weight, not size, makes hierarchy inside a message: bold lead-in phrases, bold product names in
   summaries, bulleted structure.
3. Numbers that count use tabular figures and carry their unit and denominator: "0.22 / 5", "1% used",
   "+2021", "1021s", "6.17s", "4 of 4 answered".

## 4. The composer

1. **One primary button, three states**: voice/speak when empty, send when there's text, **stop while
   working** - always the same place and shape. *(Convergent across ChatGPT, Claude, Grok, Perplexity.)*
2. **Two rows on Claude/Grok/Perplexity**: text on top; a control row of `+`, one model/mode pill, mic,
   primary. ChatGPT keeps a single row and moves model choice out of the composer. *(Split.)*
3. **The model pill states model and effort together** ("Sonnet 5 Medium", effort in secondary color),
   and the picker discloses cost where you choose: "Recommended", "5x or more usage", "higher effort uses
   your limits faster" (Claude), locked modes show a lock up front (Perplexity).
4. **`+` opens one menu for everything that adds context**: camera/photos/files as tiles, then
   connectors, skills, projects, memory as rows. Popover anchored to the button for short menus
   (ChatGPT, Grok), sheet when it has toggles (Claude).
5. **The field stays live while the agent works** (Perplexity's "Ask a follow up..." with stop inside it).
6. Quota appears at the point of use: "1 upload remaining today" under the upload tiles.

## 5. Streaming, thinking and agentic work

1. **Reasoning is one quiet row, named by a fact**: "Thought for 14s" (v0), "2 steps completed"
   (Perplexity), a one-sentence summary of what was done (Claude). Never a bare "Thinking..." once
   finished. Tap to expand; the answer is never pushed down by reasoning.
2. **Long runs narrate.** Grok and v0 interleave short first-person status paragraphs ("Next I'll
   scaffold the shell...") with collapsed rows. The narration is what a human reads; rows are evidence.
3. **Live work has a clock**: the active step shows a spinner and ticking seconds ("Searching ... 10s");
   the finished turn shows total elapsed in its footer.
4. **Checkpoints punctuate**: a version/summary card with a preview action, then "25 files changed
   +2021" (v0). That card is where review starts and the natural payload for a notification.
5. **Subagents surface as a count chip** ("1 agent used") that opens a sheet listing each agent with its
   live activity line (Grok).
6. **Agent questions get a form, not a wall of text**: a card with a pager (1/3), lettered options with
   descriptions, a free-text fallback, Skip / Next (Grok, v0). It does not block reading: a transcript
   card says "4 questions to answer", answering opens a sheet, and the card then collapses to a compact
   answers summary plus an auto-recorded reply (v0).
7. **The plan is a checklist** with the current item marked live (v0 dashed ring).
8. **Scroll-to-latest** is a small floating circle above the composer whenever you're scrolled up.
9. **After an answer**: an action row (copy, share, retry, feedback, elapsed) and suggested follow-ups as
   reply-arrow rows (ChatGPT, Grok, Perplexity).

## 6. Waiting, errors and limits

1. **Limits are inline and calm.** When a run hits a limit, the transcript gets a card where the work
   stopped: what happened, one line, one action (Grok). No modal.
2. **Usage pages show three facts**: how much is used (percent or used / total), **the exact reset**
   (date and time, or "in 30 days"), and what consumed it (per-feature breakdown). Extra credits sit
   below with balance, buy, auto top-up (Grok, v0, Orca's per-account 5h/7d bars).
3. **Errors say what to do on the other side.** Duet's empty discovery tells you what to enable on the
   computer; Orca replaced an endless "Connecting via relay..." with "your desktop is asleep / closed /
   signed out" states.
4. **Failed sends keep the text** ("Not sent", text returned to the draft - Orca). Interrupted replies
   are shown as ended with a reason, never left spinning.
5. Loading is one loader family per app (Claude's star, Grok's dot grid, Perplexity's dots).

## 7. Empty and first-run states

1. **Two lines and one action**: small icon in a soft circle, a title saying what this is, one line
   saying what will appear here, one pill. *(Convergent: Claude, ChatGPT, Grok, Perplexity, v0.)*
2. **Or make the empty state the first step** (Termius's host field inside the empty state; ChatGPT's
   Codex "Connect" button).
3. Home on AI apps is the composer plus a greeting and at most three starter actions; announcements are
   a dismissible card docked to the composer, never a modal.
4. Permission priming shows a **realistic example** of the notification you'll get (Windy, Open) and
   promises it can be changed later; the success state confirms with a small check pill.

## 8. Navigation and presentation

1. **Drawer = nav rows + recents + one floating "New" pill**; search lives at the bottom.
2. **Menus are popovers anchored to their trigger**; destructive items last, red, after a divider; long
   menus open with a provenance caption ("Added on ...").
3. **Sheets for choices with explanations** (model, effort, connect GitHub, questions); settings are a
   modal with X, account card first, then grouped sections, a floating "Search settings" pill (Grok).
4. **Explain before redirecting** (v0's GitHub sheet lists the three things that will happen).
5. Long-press a row = lifted preview + every action (Spark).

## 9. Microcopy tone

- First person from the agent, present-progressive while working, past tense when done: "I'll read the
  project instructions first", "Read globals.css", "Themed the app green".
- Facts over feelings: "Thought for 3s", "2 steps completed", "Resets Fri at 10:35 AM", "0.22 / 5".
- One label per intent per app ("New chat" everywhere in Claude; "Connect" everywhere in v0).
- Settings copy states the consequence, and what happens when off.
- Calm about limits ("You've hit your limit. Top up to keep going.") - one sentence, one action.

## 10. Notifications

1. Notifications exist for **long work finishing** and **the app needing you**, nothing else by default
   (Grok's single toggle; ChatGPT's "tell you when tasks are done").
2. Per-feature delivery choice where work is scheduled (Grok automations: Push / Email).
3. Cross-device: dismissing on one device dismisses on the other, missed ones replay on reconnect (Orca).
4. Live Activities and widgets live under an "Extensions" group in settings (Flighty), each with a
   content picker previewed as a lock screen (Athan, Timery).
