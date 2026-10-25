# Train-Gap Recorder

An iPhone app that records the connectivity on a real NYC subway ride, for [Train-Gap](https://github.com/nikokozak/train-gap). Train-Gap replays these recordings as a local proxy, so that developers can see what their apps do in a tunnel.

While it records, the app saves one event per line ([NDJSON](https://github.com/nikokozak/train-gap/blob/main/schemas/recording.v1.schema.json)):
- an HTTPS probe every second: success or failure, the round trip, and the network path and radio type (LTE, NR)
- five UDP requests every second (STUN, to `stun.cloudflare.com`), for packet loss
- the accelerometer (20 Hz), so that Train-Gap can find the stops
- the station marks and anomaly marks that you tap

It does not save your location. It asks for location access only to keep running while the phone is locked.

## Install

You need a Mac with Xcode and an iPhone with iOS 18.2 or later.

1) Connect your iPhone (unlock it, and tap "Trust" if it asks).
2) iPhone: Settings → Privacy & Security → **Developer Mode** → On.
3) Open `TrainGapRecorder.xcodeproj`. In Signing & Capabilities, for the app and for the widget extension:
   - Team: your Apple Developer team
   - Bundle Identifier: your own, for example `com.yourname.TrainGapRecorder` (and `com.yourname.TrainGapRecorder.Widgets` for the extension)
4) Select your iPhone as the run destination, and press **Run** (▶).

If iOS says "Untrusted Developer": Settings → General → VPN & Device Management → trust your developer certificate.

## Record a ride

Before the first ride:
- Allow location access when the app asks. It keeps the app running while the phone is locked. The app does not save your location. Without it, keep the app open with the screen on.
- Turn Wi-Fi off. Otherwise you measure station Wi-Fi, not cellular service. The app shows a warning when Wi-Fi is on.

On each ride:
1) Choose **Line**, **Direction**, **Starting station**, and **Carrier**. The app remembers them for the next ride.
2) On the platform, tap **Start recording**. The ride screen charts the last minute, one column per second: service, the round trip of each probe, UDP loss, and motion. Motion should rise when the train moves and fall at stops; if it stays flat, the phone records no motion.
3) Lock the phone and put it away. Recording continues while the phone is locked. The lock screen (and the Dynamic Island) shows that it records, the time, and whether there is service.
4) Optional: tap **Station** when the doors open, and **Anomaly** when something is unusual, for example the train stops between stations. The buttons are in the app and on the lock screen; they work without unlocking. A mark is a timestamp only. Station marks let you check the stop detection; anomaly marks are listed in the summary.
5) When you get off, tap **Stop**, then choose the station where you got off. **Not sure** is a valid answer. If the ride went wrong (for example, the wrong train), tap **Discard this ride** instead: the recording is deleted.

Stay in one car. If you tap Stop late, after the stairs, that is fine: Train-Gap leaves out the walk.

## Share a recording

Open **Sessions** and tap a recording. It shows the length, where you got off, and the notes. From there:
- **Share recording** sends the `.ndjson` file (AirDrop, Files, and so on).
- **Add note** adds a note to the file, for example "phone in a pocket" or "held at Atlantic Av for 3 min".
- **Delete recording** deletes the file. The app asks first; this cannot be undone.

## Turn a recording into a ride

Train-Gap has the tools. In a Train-Gap checkout:

```bash
go run ./cmd/recording-summarize -- path/to/session.ndjson   # the stops it found
go run . --ride path/to/session.ndjson                       # ride it
go run ./cmd/ride-export path/to/session.ndjson              # write a ride file to rides/
```

See [Recordings](https://github.com/nikokozak/train-gap/blob/main/docs/recordings.md) in Train-Gap: how the stops are found, how to check them, and what a ride file keeps.

## Project layout

- `TrainGapRecorder/`: the app. `Recorder` runs the probes and writes the file; `StunProber` measures UDP loss; `RideCharts` draws the last minute.
- `TrainGapRecorderWidgets/`: the widget extension, for the Live Activity on the lock screen and in the Dynamic Island.
- `Shared/`: in both targets. The Live Activity data, the intent behind the Station and Anomaly buttons, and the line badge.
- `TrainGapRecorderTests/`: unit tests (`xcodebuild test`, or ⌘U in Xcode).

## Station dataset

`TrainGapRecorder/lines.json` is a copy of Train-Gap's `internal/lines/lines.json`, built from MTA GTFS. Station IDs are GTFS stop IDs, so recordings and Train-Gap use the same IDs. After Train-Gap rebuilds its dataset, copy it here:

```bash
cp ../train-gap/internal/lines/lines.json TrainGapRecorder/lines.json
```

## License

MIT. See [LICENSE](LICENSE).
