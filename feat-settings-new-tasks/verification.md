New Tasks slice 2 verification

The Debug app is built from feat/settings-new-tasks in its own worktree. Instance: rd-settings-newtasks. Plainly is enabled by a Boolean experiment.NativeSettingsPlainly in that instance's defaults. The capture script checks screenlocked before each capture, uses drive.sh only, and quits the instance after each scenario.

Revision: a4299a19b2d618cb9f24db5b31c303973da6120a (rebased on main 1970d0db).

Checks completed:

- TaskDefaults: 8 tests covering precedence, missing/forbidden choices, estimates and declared instruction metadata.
- NativePolicy: 41 tests including organization identity/contact, invalid identity and managed precedence.
- Modes: 17 resolver/instruction tests.
- ACP: 20 new-session and saved-choice tests.
- NativeCommands: 5 keyboard-document tests.
- Settings regression harness: scoped defaults, persistence, Reset, policy receipts, removed modes/options, Undo, navigation and links.
- Changed Swift file lint and git diff whitespace checks.

UI matrix: populated all-project defaults, an inherited source popover, project defaults, expanded instructions/tools/skills, failed/disabled/required loads, managed permissions and organization contact, empty choices/inventory, an unavailable saved model, no agents enabled, and a 700-point window. Both appearances. Fixtures are inert and contain fictional content. The context estimate retains about and marks uncounted items. Required/unsupported settings use their real capabilities rather than fake switches.

The background driver reports covering windows at times. Captures are inspected against the accessibility contents. Its menu cleanup can send Escape through to Close Settings, so project links are used to reach scoped pages. Focus-dependent menu dismissal and keyboard traversal remain a manual check. No window is raised and no other app is automated.

Backend limits: policy currently forbids named permission choices; it does not declare an ordered permission ceiling or a model lock. The receipt describes that actual allowed set. Preflight cannot know all inherited/conditional agent context. Instruction metadata and tool/skill definitions produce approximate costs; existing matching reports can improve them. An MCP probe failure is not treated as proof that the agent's authentication expired.

Next slices: persisted provenance in the composer's existing settings popover, feature presets, agent detail pages, and the shared While You're Away receipt. Provider routing/model-lock receipts need enforceable backing APIs before presenting them as policy.

Behavior checks use the seeded fake agent, outside screenshot fixtures. Global Beta/High and project Low/Plan were written through Settings, persisted across relaunch, and kept separate. A new task in the other project reported Beta/High. A new task in pier reported mode=plan model=beta effort=low. The Plan instructions attach to the first prompt; the second config probe reads the actual values.

A valid skill and a malformed skill with the same folder name were placed in separate fixture projects. Before the fix, the valid project showed the other project's read error. After the fix, only the selected project's inventory determines its description, error and context cost.

Final Debug build and repository warning check passed. The settings regression harness passed on the final rebased revision. Release/Nightly compilation and the iPad check are tracked in the PR validation results.
