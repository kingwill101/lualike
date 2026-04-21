# love2d_test_bed

Runnable Flutter example for `package:love2d`.

The app loads [`assets/scripts/test_bed.lua`](./assets/scripts/test_bed.lua)
through the LOVE compatibility runtime and presents it in an adaptive workspace:

- Wide windows show the live viewport and the Lua source side by side.
- Narrow windows switch to a tabbed layout.
- `Reload Script` recreates the harness so Lua changes can be exercised quickly.

Run it with:

```bash
flutter run -d linux
```

Additional vendored LOVE demos are available through alternate entrypoints:

```bash
flutter run -d linux -t lib/main_pong.dart
flutter run -d linux -t lib/main_example_browser.dart
flutter run -d linux -t lib/main_pocket_bomber.dart
```

The example browser sources are cloned from
`love2d-community/LOVE-Example-Browser` into
[`assets/love_example_browser/`](./assets/love_example_browser/).

Pocket Bomber is cloned from `chongdashu/love2d-pocket-bomber-game` into
[`assets/pocket_bomber/`](./assets/pocket_bomber/).
