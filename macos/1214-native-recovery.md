# Hub 1214 native recovery contract

DeckPage conceals audience content against a native black background and overlay content against a transparent background on initial load, Reload Deck, and web-process termination. The native container stays in place while WebKit reloads. OverlayOutput sends transparent frames during restoration and rejects snapshot completions from an earlier restoration or output run.

After `ready`, DeckController pushes the current state with a fresh UUID token. The recovery bridge calls:

```javascript
window.presenter.apply({index, black, timerStart}, token);
```

The expected acknowledgement on `window.webkit.messageHandlers.presenter` is:

```javascript
{type: 'applied', token: token}
```

It must follow state application. Only the most recent pending token for that native view reveals the page; stale, missing, malformed and duplicate acknowledgements do not. An acknowledgement has no DeckCommands and does not trigger another broadcast.

The combined template at f4c8e52 does not send acknowledgements and ignores the extra apply argument. `BridgeScript.apply(_:acknowledgement:)` supplies a compatibility shim: it calls the existing synchronous presenter.apply and posts the acknowledgement after two requestAnimationFrame callbacks. If apply is unavailable or throws, no acknowledgement is posted and the cover stays in place. There is no timeout that exposes unacknowledged content.

The parallel template change can accept the second `token` argument and post the same message after applying state and reaching its render boundary. Duplicate messages from the native shim and template are harmless. Remove the native shim only when every supported deck emits the tokenized acknowledgement. An un-tokenized `{type: 'applied'}` is intentionally insufficient to reveal a view.

## Mac validation still required

No Swift toolchain is available on this host; this implementation has not been compiled. Verify the marked AppKit/WebKit/Accelerate sites on Swift 5.9/macOS 13. In particular, confirm that the scaled preview keeps the web viewport and snapshots at 1920x1080 independently of preview resize/Retina scale, alpha concealment permits WebKit animation-frame callbacks, and the restored content is painted when revealed. Double requestAnimationFrame is a render scheduling shim, not proof of GPU presentation or completion of the template's CSS transitions. Exercise blacked state, a nonzero slide, Cmd-R, web-process termination and an in-flight snapshot across stop/restart. No such live checks were run here.
