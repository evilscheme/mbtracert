# MenubarTracert

A macOS menubar app that provides continuous graphical traceroute monitoring, like [mtr](https://github.com/traviscross/mtr) but native and always a click away.

![screenshot](docs/screenshot.png)

## Features

- **Live traceroute** — continuous probing with per-hop latency, loss, and hostname resolution
- **Menubar sparkline** — at-a-glance latency graph right in your menubar
- **Time-normalized heatmap** — scrolling history visualization with multiple color schemes
- **Adaptive probing** — faster updates when the panel is open, slower when idle
- **Configurable** — probe intervals, history window, max hops, DNS resolution, color schemes

## Requirements

- macOS 14.6+
- Xcode 15+ (to build)

## Building

1. Open `MenubarTracert/MenubarTracert.xcodeproj` in Xcode
2. Build the **MenubarTracert** scheme
3. The app must run from `/Applications` for the privileged helper daemon to register. 

## Architecture

Two-process design: an unprivileged SwiftUI menubar app communicates over XPC with a privileged helper daemon that sends raw ICMP packets.

```
MenubarTracert.app (SwiftUI)
    │  XPC
    ▼
TracertHelper (privileged daemon, ICMP via raw sockets)
```

The helper is registered as a launchd daemon via `SMAppService` and runs as root to access `SOCK_RAW`.

## License

[MIT](LICENSE)
