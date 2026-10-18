# Accessibility

What Native promises to assistive technology and to tools that read and write text through the
macOS Accessibility API: VoiceOver, Voice Control, and dictation apps such as Wispr Flow,
Superwhisper and macOS Dictation. Keyboard use is in [keyboard.md](keyboard.md).

## The composer's text contract

Dictation tools find the focused text field, read what's around the cursor, and insert text there.
The composer's editor is a plain `TextEditor`, so it gets AppKit's text view accessibility. These
are the parts Native relies on and keeps working. They were checked against a running build with
an AX client.

| Attribute | Contract |
| --- | --- |
| `AXRole` / `AXDescription` | `AXTextArea`, described as "Message" |
| `AXFocused` | Readable and settable. ⌘L focuses it from anywhere in the window, and it stays focused while the composer floats over the transcript |
| `AXValue` | The whole draft. Writing it replaces the draft |
| `AXSelectedText` | Writing it replaces the selection, or inserts at the cursor. This is how AX-based tools insert |
| `AXSelectedTextRange`, `AXSelectedTextRanges` | Readable and settable, in UTF-16 units |
| `AXNumberOfCharacters`, `AXInsertionPointLineNumber`, `AXVisibleCharacterRange` | Readable |
| Parameterized | `AXStringForRange`, `AXAttributedStringForRange`, `AXBoundsForRange`, `AXLineForIndex`, `AXRangeForLine`, `AXRangeForPosition`, `AXRangeForIndex`, `AXReplaceRangeWithText` |

The composer reacts to every way text arrives, not only to typing:

- **AX writes.** Writing `AXValue` or `AXSelectedText` updates the draft at once. The Send button
  appears, and the `/` command and `@` file lists open for a command or mention at the cursor.
- **Paste.** Paste inserts plain text at the cursor and the editor grows to fit. Wispr Flow inserts
  this way: it pastes through the clipboard and restores the clipboard about half a second later.
- **Return.** A tool that ends a dictation with Return sends the message, or queues or steers a
  follow-up, exactly as typing Return would (keyboard.md, Sending). While the `/` or `@` list is
  open, Return picks the highlighted entry instead.

Known gaps, both from AppKit's text view:

- `AXBoundsForRange` with an empty range (the bare cursor) reports a rectangle one line above the
  cursor. Non-empty ranges are exact. Tools that place UI at the cursor should ask for one
  character.
- `AXPlaceholderValue` is absent. The placeholder is drawn by SwiftUI, and
  `AXInsertionPointLineNumber` reports `NSNotFound` while the draft is empty.

## File tagging from dictation

Wispr Flow's file tagging turns a spoken filename into an `@` tag, but only in the Cursor and
Windsurf chat inputs. It matches filenames visible in the editor and drives that editor's own `@`
autocomplete. Native isn't on that list, so Flow leaves "at README.md" as spoken words there.

Native's `@` mentions accept the same result by other routes:

- Dictated or pasted `@` text works directly. Any `@name` at the cursor opens the file list with that
  query, as if typed, and Return or Tab replaces it with the file's path.
- Text that ends up containing `@path` without the list (the cursor moved past it, or the list was
  dismissed) goes to the agent as typed. Agents read `@path` as a file reference.

Sources: [Use Flow with Cursor, VS Code, and other IDEs](https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides)
(file tagging, clipboard insertion, Accessibility permission for reading context), and
[Tanay Kothari on X](https://x.com/tankots/status/1955643960946499657) (file tagging in Cursor and
Windsurf).

## Checking it

Drive only your own instance, by pid, as AGENTS.md asks. An AX client reads the attributes above
from the `AXTextArea` described "Message", writes `AXSelectedText`, then checks that the Send
button and the `@` list appear. Accessibility Inspector shows the same tree by hand.
