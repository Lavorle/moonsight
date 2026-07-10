///|
/// Platform audio backend interface.
///
/// Logical mixer owns BGM/SE identity and volume; backends apply platform
/// playback (Web Audio / HTMLAudio in the browser host, no-op in tests).

///|
/// Discrete commands emitted to a queue backend for host/JS drainage.
pub(all) enum AudioEvent {
  PlayBgm(resource~ : String, looped~ : Bool, volume~ : Double)
  StopBgm
  PlaySe(resource~ : String, volume~ : Double)
} derive(Debug, Eq)

///|
/// Backend that actually starts/stops sounds.
pub(open) trait AudioBackend {
  fn play_bgm(Self, resource : String, looped : Bool, volume : Double) -> Unit
  fn stop_bgm(Self) -> Unit
  fn play_se(Self, resource : String, volume : Double) -> Unit
}

///|
/// No-op backend for pure logical tests and headless runs.
pub(all) struct NullBackend {
  /// Placeholder so the type is constructible (empty structs are awkward).
  dummy : Int
} derive(Debug)

///|
pub fn NullBackend::new() -> NullBackend {
  { dummy: 0 }
}

///|
pub impl AudioBackend for NullBackend with fn play_bgm(
  self,
  resource,
  looped,
  volume,
) {
  ignore(self)
  ignore(resource)
  ignore(looped)
  ignore(volume)
}

///|
pub impl AudioBackend for NullBackend with fn stop_bgm(self) {
  ignore(self)
}

///|
pub impl AudioBackend for NullBackend with fn play_se(self, resource, volume) {
  ignore(self)
  ignore(resource)
  ignore(volume)
}

///|
/// Records events for a host (or test) to drain and apply.
pub(all) struct QueueBackend {
  mut events : Array[AudioEvent]
} derive(Debug)

///|
pub fn QueueBackend::new() -> QueueBackend {
  { events: [] }
}

///|
pub impl AudioBackend for QueueBackend with fn play_bgm(
  self,
  resource,
  looped,
  volume,
) {
  self.events.push(PlayBgm(resource~, looped~, volume~))
}

///|
pub impl AudioBackend for QueueBackend with fn stop_bgm(self) {
  self.events.push(StopBgm)
}

///|
pub impl AudioBackend for QueueBackend with fn play_se(self, resource, volume) {
  self.events.push(PlaySe(resource~, volume~))
}

///|
/// Number of pending events.
pub fn QueueBackend::len(self : QueueBackend) -> Int {
  self.events.length()
}

///|
/// Read event at index without removing it (None if OOB).
pub fn QueueBackend::get(self : QueueBackend, i : Int) -> AudioEvent? {
  if i < 0 || i >= self.events.length() {
    None
  } else {
    Some(self.events[i])
  }
}

///|
/// Drain and return all pending events (clears the queue).
pub fn QueueBackend::take(self : QueueBackend) -> Array[AudioEvent] {
  let out = self.events
  self.events = []
  out
}

///|
/// Clear without returning.
pub fn QueueBackend::clear(self : QueueBackend) -> Unit {
  self.events = []
}
