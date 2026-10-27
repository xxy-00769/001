# v12 Camera-Candidate Trial

Pending. v11 four-key RULE TEST is user-accepted and remains the rollback build.
No v12 download has occurred.

## One Goal

Real CMOS1 image-derived lane candidates drive the same KEY1 left, KEY2 right,
KEY3 force, KEY4 cancel interaction. The panel must say `LOCAL CANDIDATE`, not
`RULE TEST`. No automatically rotating rule input may drive this build.

## Bounded Acceptance Set

Use 6 scenes, first as still images presented to the actual camera:

1. Two visible continuous lane boundaries in the configured lower image region.
2. Two visible dashed boundaries.
3. Left continuous / right dashed.
4. Left dashed / right continuous.
5. No usable pair (blank scene or covered lens, without disconnecting hardware).
6. Indoor furniture/lines as a non-road negative.

For each scene, record the actual left/right candidate state, displayed source
frame, left/right request behavior, force/alarm and cancel. Two repeats per scene
are enough for initial functional screening (12 observations); this is not a
training set or a statistical accuracy claim. Do not loosen validity simply
because a real image yields UNKNOWN.

If the existing heuristic cannot produce correct usable types on the four
positive scenes, record the actual failure and stop threshold guessing. Keep
v11 for deterministic rule demonstration and use the planned ARM perception
path for robust recognition after hardware communication is available.

Unknown, invalid or old results must cancel the new request/alarm state.
The panel is latest-result UI, not a promise of exact source/background frame
alignment. Existing pre-DDR HUD and background can freeze if the camera stops;
new-panel timeout is not whole-video disconnect handling.

No physical driving output is connected. A dashed candidate is not a safety
decision. This stage does not accept semantic road, pedestrians, traffic lights,
navigation, ARM communication or four-camera processing.

Programming only after a named artifact passes build checks and the applicable
user authorization is clear. JTAG volatile configuration is separate from
Flash; this document authorizes neither.
