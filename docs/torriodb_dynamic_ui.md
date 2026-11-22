# PlayTorrio: Torriodb live-programmable iOS overlays

The iPad app supports owner-configured Flutter UI panels stored in private Torriodb. This is available **after installing the first iOS build containing this feature**. Future layout, labels, colors, positions, visibility rules and supported button/slider/switch actions change in Torriodb without rebuilding the IPA.

## Configuration path

`mghazalyh/torriodb` (`main`):

```text
playtorrio/control/ios/ui/<deviceId>.json
```

The iOS client reads its **own device-scoped** JSON on the existing 12-second Torriodb polling cadence, in parallel with command polling. Missing configuration hides panels. Invalid JSON is rejected without taking down playback or other remote commands. Existing authorization for Torriodb diagnostics must be enabled.

## Complete example

```json
{
  "schema": 1,
  "enabled": true,
  "panels": [
    {
      "id": "player-tools",
      "anchor": "bottomRight",
      "when": "playing",
      "width": 235,
      "margin": 12,
      "background": "#D9151B2A",
      "items": [
        {"type": "text", "text": "PlayTorrio Live Controls", "bold": true, "fontSize": 14},
        {
          "type": "button",
          "label": "STOP SURFING · STAY HERE",
          "action": "adaptive_stop",
          "args": {},
          "color": "#FFAF3434"
        },
        {
          "type": "row",
          "children": [
            {"type": "button", "label": "HOME", "action": "app_navigate",
             "args": {"destination": "home"}},
            {"type": "button", "label": "STOP PLAN",
             "action": "diagnostic_plan_cancel", "args": {}}
          ]
        }
      ]
    }
  ]
}
```

## Declarative UI schema

* Up to **8** simultaneous panels, **96** nodes overall, **4** nesting levels. A panel has a stable `id`, `items`, optional `width` (120–700), `margin` (0–100), `background`, `anchor`, and `when`.
* Anchors: `topLeft`, `topRight`, `topCenter`, `bottomLeft`, `bottomRight`, `bottomCenter`, `center`.
* Visibility: `always`, `playing`, `notPlaying`. Playback visibility updates while the app is in the foreground.
* Nodes: `text` (text, bold, fontSize, color, align), `button` (label, action, args, color), `switch` (label, value, action, args), `slider` (label, value, min, max, action, args), `row`, `column`, `divider`, `space` (height).
* Colors use `#AARRGGBB`, for example `#FFAF3434` is an opaque red.
* The supported native action names are `adaptive_stop`, `diagnostic_plan_cancel`, `diagnostic_plan_status`, `open_channel`, `live_channel_switch`, `app_navigate`, `settings_update`, `settings_inspect`, `player`, `remote`, `state`, and `player_verify`.
* `button` submits its configured action and arguments through the existing in-app dispatcher. `switch` and `slider` also submit `value` with the user-selected value.
* Adaptive stop changes `playtorrio/control/ios/adaptive_surf/<deviceId>/config.json` to `enabled: false`. It does not close the active player. The external GitHub controller must observe the disabled flag before attempting another command.

### Live updates

1. Edit and commit `ui/<deviceId>.json` in the private Torriodb repository.
2. The running iOS client picks up the new revision on a subsequent poll without navigation or restart.
3. Change `enabled` to `false` to remove all panels, or remove the config file.
4. Configuration changes do not alter the app binary.

## Trust and limitations

This is a native **declarative UI runtime**, not an interpreter for arbitrary Dart source, JavaScript, WebViews, shell commands, filesystem access or unapproved network requests. A UI control can invoke only previously compiled native actions. To add an entirely new widget primitive or native capability, modify source and install a new IPA once. This keeps device credentials and local storage out of remote content.

The private Torriodb account controls the configuration. Never publish GitHub tokens, stream URLs, signing material or other secrets into the JSON.

## Adaptive surfing behavior

The separate Torriodb GitHub workflow `.github/workflows/playtorrio-adaptive-surf.yml` drives already-compiled iOS actions, waits 30 seconds per candidate, verifies advancing native video over a 5-second sample, persists every channel result, prunes failures **at the end of each pass**, then keeps cycling the surviving channels. The controller resumes at the first unverified channel after interruption and automatically dispatches GitHub workflow continuations before the Actions job time limit. This is not a ChatGPT scheduled task. When device acknowledgements are delayed, the controller keeps the channel pending instead of classifying it as bad content.
