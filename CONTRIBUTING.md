# Contributing

Read the [maintainer guide](source_code/MAINTAINERS.md) before editing hooks or moving Lua sections. Describe the problem, resulting behavior, relevant game/UEVR builds and validation. Report headset checks separately from automated checks.

Keep changes scoped for staged testing. Preserve user camera settings and native behavior outside the intended change. Aircraft-offset contributions should include the exact class key, cockpit view and tested values.

Keep tests and recorded fixtures in the private development workspace. Do not add test runners, private screenshots/recordings, telemetry, logs, saves, extraction keys/tools, game archives, backups or generated recovery/cache files to public exports. Inert compile-time fixture interfaces may remain in source; player builds never enable them.

Build into ignored `source_code/build`. Update the install DLL and assets together after validation. Keep the feature/configuration guides aligned with implementation.

The project-wide source license has not yet been selected by the owner. Preserve third-party notices; their licenses do not automatically cover other project or game-derived material.
