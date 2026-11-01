# ShotlistKit

The library your app links so [Shotlist](https://digitalhopeltd.com/shotlist) can capture its App Store screenshots from code, across every device, locale and appearance.

ShotlistKit lets you describe each screenshot as a **scene**: your app's real root view or view controller, taken to one screen and filled with fixture data. The Shotlist engine launches your app in its own simulators, shows each scene, waits until it's ready, and captures it. Readiness, HTTP fixtures, pinned dates and the rest are covered in the [user guide](https://digitalhopeltd.com/shotlist/guide).

**Every symbol is inside `#if DEBUG`.** Release builds contain none of it, and [`scripts/check-release-symbols.sh`](scripts/check-release-symbols.sh) proves that in CI.

## Add it to your app

In Xcode, choose File › Add Package Dependencies…, enter

```
https://github.com/richiehopedbt/ShotlistKit
```

and add **ShotlistKit** to your app target. In XcodeGen:

```yaml
packages:
  ShotlistKit:
    url: https://github.com/richiehopedbt/ShotlistKit
    from: 0.1.1
targets:
  MyApp:
    dependencies:
      - package: ShotlistKit
        product: ShotlistKit
```

| Product | For |
| --- | --- |
| `ShotlistKit` | Every app: scenes for SwiftUI, UIKit and deep links, readiness, holds and fixtures. |
| `ShotlistDependencies` | Apps using [swift-dependencies](https://github.com/pointfreeco/swift-dependencies): pins the date, UUIDs, clock and locale in each scene. |
| `ShotlistTCA` | Apps built with the [Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture): `TCAScene`. |
| `ShotlistMacros` | `@Shot`, which writes your app's `body` so it hosts the scenes with no `#if DEBUG` in your `App`. |

Xcode resolves swift-dependencies, the Composable Architecture and swift-syntax when you add the package, but links only the products you choose. ShotlistKit needs iOS 17 or later.

## Host the scenes in one line

With `ShotlistMacros` linked too, `@Shot` writes your app's `body`. You write `root`, your app's normal root view:

```swift
import ShotlistMacros
import SwiftUI

@main
@Shot
struct LarderApp: App {
    var root: some View {
        RootView()
    }
}
```

When Shotlist launches the app, the body shows the Shotlist host with your `Screenshots.scenes`. Otherwise, and in every Release build, it's just `WindowGroup { root }`. Import ShotlistMacros outside `#if DEBUG`, so `@Shot` exists in Release too; it declares nothing but the macro. The [user guide](https://digitalhopeltd.com/shotlist/guide/setup) covers link scenes that need their own root, and hosting the scenes yourself.

## Versions

Use a ShotlistKit release from the same minor version as your Shotlist app and command-line tool: 0.1.x with Shotlist 0.1. The engine checks ShotlistKit's protocol version when your app connects, and says which to update if they don't match.

## Licence

MIT. See [LICENSE](LICENSE). Shotlist itself, the engine, command-line tool and Mac app, is sold by DigitalHope through [digitalhopeltd.com/shotlist](https://digitalhopeltd.com/shotlist). This package is a copy of the app-side modules from Shotlist's own repository; please send issues and suggestions to support@digitalhopeltd.com.
