///|
/// Logical audio mixer: authoritative BGM/SE ids, volume, and loop flags.
///
/// Stage mirrors `bgm`/`se` for save snapshots; the mixer owns richer state
/// (volume, loop, SE sequence, linear BGM fade) and notifies an `AudioBackend`
/// on changes.
///
/// Output volume = logical × prefs.master × prefs.channel (prefs multiply by
/// 1.0 until the prefs system lands). BGM and SE use separate channel gains.

///|
pub(all) struct Mixer {
  mut bgm : String?
  mut bgm_loop : Bool
  mut bgm_volume : Double
  /// Target volume for an in-flight linear fade (`None` = not fading).
  mut bgm_fade_to : Double?
  /// Wall-clock seconds left for the current BGM fade (0 = done / snap).
  mut bgm_fade_remaining : Double
  /// When true, stop BGM after the fade completes (fade-out stop).
  mut bgm_fade_stop : Bool
  mut se : String?
  mut se_volume : Double
  /// Increments on every `play_se` so hosts can re-trigger the same id.
  mut se_seq : Int
  mut backend : &AudioBackend
}

///|
/// Logical BGM volume × preference gains (master/bgm default to 1.0).
fn output_bgm_volume(logical : Double) -> Double {
  // Prefs (master × bgm) land later; keep identity multipliers until then.
  logical * 1.0 * 1.0
}

///|
/// Logical SE volume × preference gains (master/se default to 1.0).
fn output_se_volume(logical : Double) -> Double {
  // Prefs (master × se) land later; keep identity multipliers until then.
  logical * 1.0 * 1.0
}

///|
/// Fresh mixer with a null (no-op) backend.
pub fn Mixer::new() -> Mixer {
  let b : &AudioBackend = NullBackend::new()
  {
    bgm: None,
    bgm_loop: true,
    bgm_volume: 1.0,
    bgm_fade_to: None,
    bgm_fade_remaining: 0.0,
    bgm_fade_stop: false,
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
    bgm_fade_to: None,
    bgm_fade_remaining: 0.0,
    bgm_fade_stop: false,
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
/// Clear any in-flight BGM fade without applying a target.
fn Mixer::clear_fade(self : Mixer) -> Unit {
  self.bgm_fade_to = None
  self.bgm_fade_remaining = 0.0
  self.bgm_fade_stop = false
}

///|
/// Start or replace BGM. `looped` defaults to true for VN background music.
///
/// Note: the label is `looped` (not `loop`) because `loop` is a MoonBit keyword.
/// Cancels any in-flight fade.
pub fn Mixer::play_bgm(
  self : Mixer,
  resource : String,
  looped? : Bool = true,
  volume? : Double = 1.0,
) -> Unit {
  self.clear_fade()
  self.bgm = Some(resource)
  self.bgm_loop = looped
  self.bgm_volume = volume
  self.backend.play_bgm(resource, looped, output_bgm_volume(volume))
}

///|
/// Stop current BGM immediately (no-op to backend if already silent).
///
/// Cancels any in-flight fade. For a fade-out stop, use `fade_bgm_to(0, d, stop=true)`.
pub fn Mixer::stop_bgm(self : Mixer) -> Unit {
  self.clear_fade()
  if self.bgm is None {
    return
  }
  self.bgm = None
  self.backend.stop_bgm()
}

///|
/// Linear fade of logical BGM volume toward `target` over `duration` seconds.
///
/// Fire-and-forget: advances on `tick(dt)`. Zero/negative duration snaps.
/// When `stop` is true, stops BGM after the fade reaches the target (fade-out).
pub fn Mixer::fade_bgm_to(
  self : Mixer,
  target : Double,
  duration : Double,
  stop? : Bool = false,
) -> Unit {
  if duration <= 0.0 {
    self.bgm_volume = target
    self.clear_fade()
    self.backend.set_bgm_volume(output_bgm_volume(target))
    if stop {
      self.stop_bgm()
    }
    return
  }
  self.bgm_fade_to = Some(target)
  self.bgm_fade_remaining = duration
  self.bgm_fade_stop = stop
}

///|
/// Advance in-flight BGM fade by wall-clock `dt` seconds; emit volume events.
///
/// Non-positive `dt` is a no-op (does not snap-complete). Zero remaining snaps.
pub fn Mixer::tick(self : Mixer, dt : Double) -> Unit {
  let target = match self.bgm_fade_to {
    None => return
    Some(t) => t
  }
  // Non-positive dt: leave fade in progress (hosts may tick with 0 during setup).
  if dt <= 0.0 {
    return
  }
  let cur = self.bgm_volume
  let rem = self.bgm_fade_remaining
  if rem <= 0.0 {
    self.bgm_volume = target
    let do_stop = self.bgm_fade_stop
    self.clear_fade()
    self.backend.set_bgm_volume(output_bgm_volume(target))
    if do_stop {
      self.stop_bgm()
    }
    return
  }
  let step_t = if dt < rem { dt } else { rem }
  let frac = step_t / rem
  self.bgm_volume = cur + (target - cur) * frac
  self.bgm_fade_remaining = rem - step_t
  self.backend.set_bgm_volume(output_bgm_volume(self.bgm_volume))
  if self.bgm_fade_remaining <= 0.0 {
    // Last step already emitted the target volume; only stop if requested.
    self.bgm_volume = target
    let do_stop = self.bgm_fade_stop
    self.clear_fade()
    if do_stop {
      self.stop_bgm()
    }
  }
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
  self.backend.play_se(resource, output_se_volume(volume))
}

///|
/// Apply logical stage mirror (e.g. after save load) without double-emitting SE.
///
/// BGM is started/stopped to match; last SE id is restored but not re-played.
/// Optional `volume` restores logical BGM gain (default keeps current / 1.0 on new play).
pub fn Mixer::apply_logic(
  self : Mixer,
  bgm : String?,
  se : String?,
  volume? : Double = 1.0,
) -> Unit {
  self.clear_fade()
  self.bgm_volume = volume
  match bgm {
    Some(id) =>
      // Avoid restarting the same track on load if already playing.
      match self.bgm {
        Some(cur) =>
          if cur != id {
            self.play_bgm(id, looped=true, volume=volume)
          } else {
            self.backend.set_bgm_volume(output_bgm_volume(volume))
          }
        None => self.play_bgm(id, looped=true, volume=volume)
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
