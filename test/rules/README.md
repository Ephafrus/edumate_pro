# Security-rules tests

Rules are the only thing standing between a signed-in stranger and another
school's data, and they cannot be exercised by `flutter test` — so they get
their own suite, run against the Firestore emulator.

These cover the **staff-invite claim path**: an invited teacher has to be able
to write their own member document on first sign-in, because nobody else is
there to do it for them, *without* that becoming a way to hand yourself a role.
Getting this wrong is not a subtle failure — invited teachers silently end up
as parents.

```bash
cd test/rules
npm install
npm test
```

Requires Java (the emulator runs on the JVM). `emulators:exec` starts the
emulator, runs the suite and shuts down, so nothing is left listening.

The suite loads `../../firestore.rules` — edit the rules, re-run, done.
