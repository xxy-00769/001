# v12 Camera-Candidate Interaction

Single objective: real CMOS1 lane candidates -> frame-tagged mailbox -> the
accepted four-key interaction -> HDMI status panel. No ARM, traffic lights,
four-camera work, new AI engine, or detector threshold changes in this stage.

The v11 RULE TEST stage was accepted by user report on 2026-10-18. Its binary,
logs and source remain unchanged. v4/v8 and user changes remain protected.

## Exit Conditions

- Use real CMOS1 pixels and `img_proc.adas_valid/adas_snapshot`, not the synthetic
  four-scene rule source. Keep `LOCAL CANDIDATE` visible.
- Keep the original picture, DDR path and KEY1/2/3/4 assignments.
- Verify atomic frame-tagged transfer, invalid/bad-frame clearing, stopped-source
  timeout, common reset and key decisions across independent clocks.
- Review the newly instantiated mailbox in mapped/routed output. A functional
  simulation alone is not physical CDC signoff. Inherited clock-group exceptions
  must not silently suppress the new bundled-data timing limit.
- Build a separate named bitstream with matching mask and immutable evidence.
- On an explicitly authorized trial, verify real-camera behavior. This is still
  heuristic lane classification, not semantic road recognition or safe driving.

No new download or Flash operation is performed by the build/test scripts.
Until physical acceptance, v11 remains the last user-accepted interaction build.
The status panel is latest-result UI, not a spatial overlay guaranteed to match
the DDR background frame. Camera-stop clearing only covers the new panel and
commands; the existing pre-DDR v8 HUD/background can freeze.
