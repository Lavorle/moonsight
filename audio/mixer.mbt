///|
/// Logical audio mixer: authoritative BGM/SE ids, volume, and loop flags.
///
/// Stage mirrors `bgm`/`se` for save snapshots; the mixer owns richer state
/// (volume, loop, SE sequence) and notifies an `AudioBackend` on changes.

///|
pub(all) struct Mixer {
  mut bgm : String?
  mut bgm_loop : Bool
  mut bgm_volume : Double
  mut se : String?
  mut se_volume : Double
  /// Increments on every `play_se` so hosts can re-trigger the same id.
  mut se_seq : Int
  mut backend : &AudioBackend
}

///|
/// Fresh mixer with a null (no-op) backend.
pub fn Mixer::new() -> Mixer {
  let b : &AudioBackend = NullBackend::new()
  {
    bgm: None,
    bgm_loop: true,
    bgm_volume: 1.0,
    se: None,
    se_volume: 1.0,
    se_seq: 0,
    backend: b,
  }
}

///|
/// Mixer that forwards play/stop to a custom backend.
pub fn Mixer::with_backend(backend : &AudioBackend) -> Mixer {
  {
    bgm: None,
    bgm_loop: true,
    bgm_volume: 1.0,
    se: None,
    se_volume: 1.0,
    se_seq: 0,
    backend,
  }
}

///|
/// Replace the platform backend (e.g. install a queue for the web host).
pub fn Mixer::set_backend(self : Mixer, backend : &AudioBackend) -> Unit {
  self.backend = backend
}

///|
/// Start or replace BGM. `looped` defaults to true for VN background music.
///
/// Note: the label is `looped` (not `loop`) because `loop` is a MoonBit keyword.
pub fn Mixer::play_bgm(
  self : Mixer,
  resource : String,
  looped? : Bool = true,
  volume? : Double = 1.0,
) -> Unit {
  self.bgm = Some(resource)
  self.bgm_loop = looped
  self.bgm_volume = volume
  self.backend.play_bgm(resource, looped, volume)
}

///|
/// Stop current BGM (no-op to backend if already silent).
pub fn Mixer::stop_bgm(self : Mixer) -> Unit {
  if self.bgm is None {
    return
  }
  self.bgm = None
  self.backend.stop_bgm()
}

///|
/// Fire a one-shot sound effect. Same resource may be retriggered; `se_seq` bumps.
pub fn Mixer::play_se(
  self : Mixer,
  resource : String,
  volume? : Double = 1.0,
) -> Unit {
  self.se = Some(resource)
  self.se_volume = volume
  self.se_seq = self.se_seq + 1
  self.backend.play_se(resource, volume)
}

///|
/// Apply logical stage mirror (e.g. after save load) without double-emitting SE.
///
/// BGM is started/stopped to match; last SE id is restored but not re-played.
pub fn Mixer::apply_logic(self : Mixer, bgm : String?, se : String?) -> Unit {
  match bgm {
    Some(id) =>
      // Avoid restarting the same track on load if already playing.
      match self.bgm {
        Some(cur) =>
          if cur != id {
            self.play_bgm(id, looped=true, volume=self.bgm_volume)
          }
        None => self.play_bgm(id, looped=true, volume=self.bgm_volume)
      }
    None => self.stop_bgm()
  }
  self.se = se
}

// ---------------------------------------------------------------------------
// Process-global mixer so `std_commands` can update it without Engine holding
// an audio dependency. Hosts should `install_mixer` with a QueueBackend.
// ---------------------------------------------------------------------------

///|
let global_mixer_slot : Ref[Mixer] = Ref(Mixer::new())

///|
/// Shared mixer used by host commands (`audio.bgm` / `audio.se`).
pub fn global_mixer() -> Mixer {
  global_mixer_slot.val
}

///|
/// Install a host-owned mixer (typically backed by `QueueBackend` for JS).
pub fn install_mixer(m : Mixer) -> Unit {
  global_mixer_slot.val = m
}

///|
/// Reset to a fresh null-backed mixer (tests / new session).
pub fn reset_global_mixer() -> Unit {
  global_mixer_slot.val = Mixer::new()
}
