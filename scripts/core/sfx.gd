extends Node
## Procedurally synthesized sound effects and ambience. No audio files ship
## with the game; everything is generated at startup.

const RATE := 22050

var streams := {}
var pool3d: Array = []
var pool2d: Array = []
var world: Node3D
var ambience: AudioStreamPlayer
var fire: AudioStreamPlayer3D
var bird_t := 6.0
var listener_pos := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var ready_done := false


func _ready() -> void:
	rng.seed = 7
	if DisplayServer.get_name() == "headless":
		return
	_build()
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool2d.append(p)
	ambience = AudioStreamPlayer.new()
	ambience.stream = streams["wind"]
	ambience.volume_db = -14.0
	add_child(ambience)
	ready_done = true


func _process(delta: float) -> void:
	if not ready_done or world == null or not is_instance_valid(world):
		return
	bird_t -= delta
	if bird_t <= 0.0:
		bird_t = rng.randf_range(5.0, 16.0)
		var p := listener_pos + Vector3(rng.randf_range(-40, 40), rng.randf_range(4, 14), rng.randf_range(-40, 40))
		play("birds", p, rng.randf_range(-16.0, -8.0), rng.randf_range(0.85, 1.2))


func set_world(w: Node3D) -> void:
	world = w
	for p in pool3d:
		if is_instance_valid(p):
			p.queue_free()
	pool3d.clear()
	if w == null or not ready_done:
		if ambience:
			ambience.stop()
		return
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 9.0
		p.max_distance = 220.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		w.add_child(p)
		pool3d.append(p)
	ambience.play()


func set_fire(pos: Vector3) -> void:
	if not ready_done or world == null:
		return
	if fire == null or not is_instance_valid(fire):
		fire = AudioStreamPlayer3D.new()
		fire.stream = streams["fire"]
		fire.unit_size = 4.0
		fire.max_distance = 40.0
		fire.volume_db = -6.0
		world.add_child(fire)
	fire.global_position = pos
	if not fire.playing:
		fire.play()


func play(name: String, pos = null, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not ready_done or not streams.has(name):
		return
	if pos == null or world == null:
		for p in pool2d:
			if not p.playing:
				p.stream = streams[name]
				p.volume_db = vol_db
				p.pitch_scale = pitch
				p.play()
				return
		return
	var v: Vector3 = pos
	if v.distance_to(listener_pos) > 230.0:
		return
	var best: AudioStreamPlayer3D = null
	for p in pool3d:
		if not p.playing:
			best = p
			break
	if best == null:
		return
	best.stream = streams[name]
	best.volume_db = vol_db
	best.pitch_scale = pitch * rng.randf_range(0.94, 1.06)
	best.global_position = v
	best.play()


# --- Synthesis -------------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var g := 0.89 / peak if peak > 0.89 else 1.0
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i] * g, -1.0, 1.0) * 32767.0))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _lp(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


func _noise_hit(seconds: float, decay: float, fc: float, thump_hz: float = 0.0, thump: float = 0.0) -> PackedFloat32Array:
	var b := _buf(seconds)
	var y := 0.0
	var y2 := 0.0
	var a := _lp(fc)
	for i in b.size():
		var t := float(i) / RATE
		var env := exp(-t / decay)
		y += a * (rng.randf_range(-1, 1) - y)
		y2 += a * (y - y2)
		var v := y2 * env * 2.5
		if thump > 0.0:
			v += sin(TAU * thump_hz * t * (1.0 - t * 0.6)) * exp(-t / (decay * 1.4)) * thump
		b[i] = v
	return b


func _partials(seconds: float, freqs: Array, decays: Array, amps: Array, attack: float = 0.002) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * exp(-t / decays[k]) * amps[k]
		b[i] = v * minf(1.0, t / attack)
	return b


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gb: float = 1.0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var o := PackedFloat32Array()
	o.resize(n)
	for i in n:
		o[i] = (a[i] if i < a.size() else 0.0) + (b[i] * gb if i < b.size() else 0.0)
	return o


func _build() -> void:
	streams["chop"] = _wav(_noise_hit(0.22, 0.045, 900.0, 140.0, 0.9))
	streams["pick"] = _wav(_mix(_noise_hit(0.12, 0.02, 3000.0), _partials(0.25, [1850.0, 2730.0], [0.05, 0.03], [0.5, 0.3])))
	streams["hammer"] = _wav(_mix(_noise_hit(0.15, 0.025, 1800.0), _partials(0.2, [310.0, 620.0], [0.05, 0.03], [0.8, 0.3])))
	streams["anvil"] = _wav(_mix(_noise_hit(0.08, 0.01, 4000.0), _partials(0.9, [930.0, 1480.0, 2290.0, 3150.0], [0.35, 0.25, 0.18, 0.1], [0.6, 0.45, 0.35, 0.2])))
	streams["rustle"] = _wav(_noise_hit(0.35, 0.12, 2500.0))
	streams["bell"] = _wav(_partials(3.0, [512.0, 1030.0, 1238.0, 1612.0, 2048.0], [1.4, 1.0, 0.8, 0.6, 0.4], [0.7, 0.45, 0.35, 0.25, 0.15], 0.004))
	streams["clash"] = _wav(_mix(_noise_hit(0.12, 0.02, 6000.0), _partials(0.35, [2120.0, 3370.0, 4410.0], [0.12, 0.08, 0.05], [0.5, 0.4, 0.3])))
	streams["hit"] = _wav(_noise_hit(0.18, 0.04, 600.0, 90.0, 1.0))
	streams["ram"] = _wav(_noise_hit(0.5, 0.09, 300.0, 55.0, 1.4))
	streams["impact"] = _wav(_noise_hit(0.9, 0.18, 700.0, 45.0, 1.0))
	streams["collapse"] = _wav(_noise_hit(1.8, 0.5, 400.0, 40.0, 0.8))
	streams["arrow_land"] = _wav(_noise_hit(0.07, 0.012, 2500.0))
	streams["step"] = _wav(_noise_hit(0.09, 0.02, 500.0, 70.0, 0.3))
	streams["click"] = _wav(_partials(0.05, [1600.0], [0.01], [0.5]))
	streams["complete"] = _wav(_mix(_partials(0.9, [659.0, 988.0], [0.35, 0.3], [0.5, 0.35], 0.01), _partials(0.9, [1318.0], [0.2], [0.15], 0.02)))
	streams["birth"] = _wav(_partials(0.8, [880.0, 1320.0, 1760.0], [0.3, 0.25, 0.15], [0.35, 0.25, 0.1], 0.02))
	streams["report"] = _wav(_mix(_partials(0.35, [740.0], [0.12], [0.4], 0.01), _noise_hit(0.2, 0.05, 1500.0), 0.3))
	streams["smelt"] = _wav(_noise_hit(0.6, 0.25, 700.0))
	streams["swing"] = _wav(_whoosh(0.3, 1200.0))
	streams["bow"] = _wav(_bow())
	streams["horn"] = _wav(_horn())
	streams["cannon"] = _wav(_cannon())
	streams["age"] = _wav(_fanfare())
	streams["birds"] = _wav(_birds())
	streams["wind"] = _wav(_wind(), true)
	streams["fire"] = _wav(_fire(), true)


func _whoosh(seconds: float, fc: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	var y := 0.0
	var a := _lp(fc)
	for i in b.size():
		var t := float(i) / b.size()
		y += a * (rng.randf_range(-1, 1) - y)
		b[i] = y * sin(PI * t) * 3.0
	return b


func _bow() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in b.size():
		var t := float(i) / RATE
		var f := 170.0 * (1.0 + 0.4 * exp(-t / 0.03))
		b[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-t / 0.08) * 0.7
	return _mix(b, _whoosh(0.3, 2500.0), 0.25)


func _horn() -> PackedFloat32Array:
	var b := _buf(1.4)
	var y := 0.0
	var a := _lp(900.0)
	for i in b.size():
		var t := float(i) / RATE
		var f := 196.0 + 2.0 * sin(TAU * 5.0 * t)
		var saw := 0.0
		for k in range(1, 7):
			saw += sin(TAU * f * k * t) / k
		var env := minf(1.0, t / 0.12) * (1.0 if t < 1.0 else maxf(0.0, 1.0 - (t - 1.0) / 0.4))
		y += a * (saw - y)
		b[i] = y * env * 0.6
	return b


func _cannon() -> PackedFloat32Array:
	var b := _buf(2.4)
	var y := 0.0
	var y2 := 0.0
	var a := _lp(260.0)
	for i in b.size():
		var t := float(i) / RATE
		y += a * (rng.randf_range(-1, 1) - y)
		y2 += a * (y - y2)
		var crack := rng.randf_range(-1, 1) * exp(-t / 0.012) * 0.8
		b[i] = y2 * exp(-t / 0.55) * 7.0 + crack + sin(TAU * 38.0 * t) * exp(-t / 0.3) * 0.7
	return b


func _fanfare() -> PackedFloat32Array:
	var b := _buf(1.6)
	var notes := [[0.0, 392.0], [0.25, 494.0], [0.5, 587.0], [0.75, 784.0]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in notes:
			var dt: float = t - n[0]
			if dt < 0.0:
				continue
			var f: float = n[1]
			var env := minf(1.0, dt / 0.03) * exp(-dt / (0.5 if n[0] < 0.7 else 0.9))
			v += (sin(TAU * f * dt) + 0.5 * sin(TAU * f * 2.0 * dt) + 0.25 * sin(TAU * f * 3.0 * dt)) * env
		b[i] = v * 0.3
	return b


func _birds() -> PackedFloat32Array:
	var b := _buf(1.2)
	var chirps := rng.randi_range(2, 4)
	for c in chirps:
		var start := rng.randf_range(0.0, 0.8)
		var f0 := rng.randf_range(2600.0, 4200.0)
		var dur := rng.randf_range(0.06, 0.14)
		var phase := 0.0
		for i in range(int(start * RATE), mini(b.size(), int((start + dur) * RATE))):
			var lt := float(i) / RATE - start
			var k := lt / dur
			var f := f0 * (1.0 + 0.35 * sin(PI * k))
			phase += TAU * f / RATE
			b[i] += sin(phase) * sin(PI * k) * 0.4
	return b


func _wind() -> PackedFloat32Array:
	var b := _buf(8.0)
	var y := 0.0
	var y2 := 0.0
	var a := _lp(380.0)
	for i in b.size():
		var t := float(i) / RATE
		y += a * (rng.randf_range(-1, 1) - y)
		y2 += a * 0.5 * (y - y2)
		var gust := 0.55 + 0.3 * sin(TAU * t / 8.0) + 0.15 * sin(TAU * t / 2.0 + 1.0)
		b[i] = y2 * gust * 6.0
	# Crossfade the ends so the loop is seamless.
	var fade := int(0.5 * RATE)
	for i in fade:
		var k := float(i) / fade
		b[i] = b[i] * k + b[b.size() - fade + i] * (1.0 - k)
	return b.slice(0, b.size() - fade)


func _fire() -> PackedFloat32Array:
	var b := _buf(4.0)
	var y := 0.0
	var a := _lp(600.0)
	for i in b.size():
		y += a * (rng.randf_range(-1, 1) - y)
		b[i] = y * 1.2
	for k in 70:
		var at := rng.randi_range(0, b.size() - 600)
		var amp := rng.randf_range(0.3, 1.0)
		for j in rng.randi_range(80, 500):
			b[at + j] += rng.randf_range(-1, 1) * amp * exp(-float(j) / 90.0)
	return b
