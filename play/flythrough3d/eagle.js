// Eagle web runtime: loads a game compiled to wasm32-wasi, provides a minimal
// WASI polyfill plus the `eagle` import module (WebGL2, WebAudio, input).
//
//   <canvas id="eagle"></canvas>
//   <script type="module">
//     import { runEagle } from "./eagle.js";
//     runEagle("game.wasm", document.getElementById("eagle"));
//   </script>
export async function runEagle(wasmUrl, canvas, options = {}) {
  const rt = new EagleRuntime(canvas, options);
  const bytes = await (await fetch(wasmUrl)).arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, rt.imports());
  rt.start(instance);
  return rt;
}

const SCANCODES = {
  KeyA: 4, KeyB: 5, KeyC: 6, KeyD: 7, KeyE: 8, KeyF: 9, KeyG: 10, KeyH: 11, KeyI: 12, KeyJ: 13, KeyK: 14, KeyL: 15, KeyM: 16,
  KeyN: 17, KeyO: 18, KeyP: 19, KeyQ: 20, KeyR: 21, KeyS: 22, KeyT: 23, KeyU: 24, KeyV: 25, KeyW: 26, KeyX: 27, KeyY: 28, KeyZ: 29,
  Digit1: 30, Digit2: 31, Digit3: 32, Digit4: 33, Digit5: 34, Digit6: 35, Digit7: 36, Digit8: 37, Digit9: 38, Digit0: 39,
  Enter: 40, Escape: 41, Backspace: 42, Tab: 43, Space: 44, Minus: 45, Equal: 46, BracketLeft: 47, BracketRight: 48, Backslash: 49,
  Semicolon: 51, Quote: 52, Backquote: 53, Comma: 54, Period: 55, Slash: 56, CapsLock: 57,
  F1: 58, F2: 59, F3: 60, F4: 61, F5: 62, F6: 63, F7: 64, F8: 65, F9: 66, F10: 67, F11: 68, F12: 69,
  PrintScreen: 70, ScrollLock: 71, Pause: 72, Insert: 73, Home: 74, PageUp: 75, Delete: 76, End: 77, PageDown: 78,
  ArrowRight: 79, ArrowLeft: 80, ArrowDown: 81, ArrowUp: 82, NumLock: 83, NumpadDivide: 84, NumpadMultiply: 85, NumpadSubtract: 86,
  NumpadAdd: 87, NumpadEnter: 88, Numpad1: 89, Numpad2: 90, Numpad3: 91, Numpad4: 92, Numpad5: 93, Numpad6: 94, Numpad7: 95,
  Numpad8: 96, Numpad9: 97, Numpad0: 98, NumpadDecimal: 99,
  ControlLeft: 224, ShiftLeft: 225, AltLeft: 226, MetaLeft: 227, ControlRight: 228, ShiftRight: 229, AltRight: 230, MetaRight: 231,
};

// Event codes shared with src/eagle/platform/web.cr
const EV = { KEY: 1, TEXT: 2, MOTION: 3, BUTTON: 4, WHEEL: 5, RESIZE: 6, FOCUS: 7, GP_CONNECT: 8, GP_BUTTON: 9, GP_AXIS: 10, QUIT: 12 };

class EagleRuntime {
  constructor(canvas, options) {
    this.canvas = canvas;
    this.options = options;
    this.events = [];
    this.objects = [null]; // GL object table (id -> object)
    this.locations = [null]; // uniform locations
    this.textInput = false;
    this.audio = null;
    this.gamepads = new Map();
    this.exports = null;
    this.running = false;
    this.decoder = new TextDecoder();
    this.encoder = new TextEncoder();
    this.gl = null;
    this.stdout = "";
    this.stderr = "";
  }

  // ---- memory helpers ------------------------------------------------------
  get mem() { return this.exports.memory; }
  u8(ptr, len) { return new Uint8Array(this.mem.buffer, ptr, len); }
  i32(ptr, len) { return new Int32Array(this.mem.buffer, ptr, len); }
  u32(ptr, len) { return new Uint32Array(this.mem.buffer, ptr, len); }
  f32(ptr, len) { return new Float32Array(this.mem.buffer, ptr, len); }
  str(ptr, len) { return this.decoder.decode(this.u8(ptr, len)); }
  cstr(ptr) {
    const bytes = new Uint8Array(this.mem.buffer);
    let end = ptr;
    while (bytes[end] !== 0) end++;
    return this.decoder.decode(bytes.subarray(ptr, end));
  }
  writeStr(ptr, len, s) {
    const bytes = this.encoder.encode(s);
    const n = Math.min(bytes.length, len);
    this.u8(ptr, n).set(bytes.subarray(0, n));
    return n;
  }
  push(...values) { this.events.push(values); }

  // ---- lifecycle -------------------------------------------------------------
  start(instance) {
    this.exports = instance.exports;
    this.exports._start();
    this.running = true;
    const frame = () => {
      if (!this.running) return;
      this.pollGamepads();
      try { this.exports.eagle_frame(); } catch (e) { console.error(e); this.running = false; return; }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  stop() { this.running = false; }

  setupCanvas(width, height) {
    const c = this.canvas;
    this.dpr = window.devicePixelRatio || 1;
    if (this.options.fill) {
      c.style.width = "100%"; c.style.height = "100%";
    } else if (!c.style.width) {
      c.style.width = width + "px"; c.style.height = height + "px";
    }
    this.resizeCanvas();
    new ResizeObserver(() => { this.resizeCanvas(); this.push(EV.RESIZE, this.logicalW, this.logicalH); }).observe(c);
    c.tabIndex = 0;
    c.style.outline = "none";
    c.addEventListener("contextmenu", e => e.preventDefault());
    const mods = e => (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
    c.addEventListener("keydown", e => {
      const code = SCANCODES[e.code] || 0;
      this.push(EV.KEY, code, 1, e.repeat ? 1 : 0, mods(e));
      if (this.textInput && e.key.length === 1 && !e.ctrlKey && !e.metaKey) {
        const cps = Array.from(e.key).map(ch => ch.codePointAt(0));
        this.push(EV.TEXT, ...cps.slice(0, 6));
      }
      if (["Space", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Tab", "Backspace"].includes(e.code)) e.preventDefault();
      this.resumeAudio();
    });
    c.addEventListener("keyup", e => this.push(EV.KEY, SCANCODES[e.code] || 0, 0, 0, mods(e)));
    const pos = e => { const r = c.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; };
    c.addEventListener("mousemove", e => { const [x, y] = pos(e); this.push(EV.MOTION, x, y, e.movementX, e.movementY); });
    c.addEventListener("mousedown", e => { const [x, y] = pos(e); c.focus(); this.push(EV.BUTTON, e.button + 1 === 3 ? 3 : e.button + 1, 1, x, y, e.detail || 1); this.resumeAudio(); });
    c.addEventListener("mouseup", e => { const [x, y] = pos(e); this.push(EV.BUTTON, e.button + 1 === 3 ? 3 : e.button + 1, 0, x, y, e.detail || 1); });
    c.addEventListener("wheel", e => { const [x, y] = pos(e); this.push(EV.WHEEL, -e.deltaX / 100, -e.deltaY / 100, x, y); e.preventDefault(); }, { passive: false });
    c.addEventListener("focus", () => this.push(EV.FOCUS, 1));
    c.addEventListener("blur", () => this.push(EV.FOCUS, 0));
    window.addEventListener("gamepadconnected", e => { this.gamepads.set(e.gamepad.index, { buttons: [], axes: [] }); this.push(EV.GP_CONNECT, e.gamepad.index, 1); });
    window.addEventListener("gamepaddisconnected", e => { this.gamepads.delete(e.gamepad.index); this.push(EV.GP_CONNECT, e.gamepad.index, 0); });
    // touch -> mouse (single finger)
    c.addEventListener("touchstart", e => { const t = e.touches[0]; const [x, y] = pos(t); this.push(EV.MOTION, x, y, 0, 0); this.push(EV.BUTTON, 1, 1, x, y, 1); this.resumeAudio(); e.preventDefault(); }, { passive: false });
    c.addEventListener("touchmove", e => { const t = e.touches[0]; const [x, y] = pos(t); this.push(EV.MOTION, x, y, 0, 0); e.preventDefault(); }, { passive: false });
    c.addEventListener("touchend", e => { const t = e.changedTouches[0]; const [x, y] = pos(t); this.push(EV.BUTTON, 1, 0, x, y, 1); e.preventDefault(); }, { passive: false });
  }

  resizeCanvas() {
    const c = this.canvas;
    const r = c.getBoundingClientRect();
    this.logicalW = Math.max(1, Math.round(r.width));
    this.logicalH = Math.max(1, Math.round(r.height));
    const pw = Math.round(this.logicalW * this.dpr), ph = Math.round(this.logicalH * this.dpr);
    if (c.width !== pw || c.height !== ph) { c.width = pw; c.height = ph; }
  }

  pollGamepads() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const gp of pads) {
      if (!gp) continue;
      const st = this.gamepads.get(gp.index);
      if (!st) continue;
      // standard mapping -> SDL button order
      const map = [0, 1, 2, 3, 9, 10, 4, 5, 8, 6, 7, 11, 12, 13, 14, 15, 16]; // standard index -> sdl button
      const sdl = [0, 1, 2, 3, 9, 10, -1, -1, 4, 6, 7, 8, 11, 12, 13, 14, 5];
      gp.buttons.forEach((b, i) => {
        const pressed = b.pressed ? 1 : 0;
        if (st.buttons[i] !== pressed) { st.buttons[i] = pressed; const sb = sdl[i]; if (sb >= 0) this.push(EV.GP_BUTTON, gp.index, sb, pressed); }
      });
      gp.axes.forEach((v, i) => {
        if (Math.abs((st.axes[i] || 0) - v) > 0.01) { st.axes[i] = v; if (i < 4) this.push(EV.GP_AXIS, gp.index, i, v); }
      });
      // triggers as axes 4/5
      [6, 7].forEach((bi, k) => { const v = gp.buttons[bi] ? gp.buttons[bi].value : 0; const key = 4 + k; if (Math.abs((st.axes[key] || 0) - v) > 0.01) { st.axes[key] = v; this.push(EV.GP_AXIS, gp.index, key, v * 2 - 1); } });
    }
  }

  resumeAudio() { if (this.audio && this.audio.ctx.state !== "running") this.audio.ctx.resume(); }

  // ---- imports -----------------------------------------------------------------
  imports() {
    const rt = this;
    const wasi = this.wasiImports();
    const eagle = {
      js_init: (w, h, titlePtr, titleLen) => { document.title = rt.str(titlePtr, titleLen) || document.title; rt.setupCanvas(w, h); rt.initGL(); },
      js_log: (level, ptr, len) => { const s = rt.str(ptr, len); (level >= 2 ? console.error : level === 1 ? console.warn : console.log)(s); },
      js_now: () => performance.now() / 1000,
      js_window_size: (ptr) => { const v = rt.i32(ptr, 4); v[0] = rt.logicalW; v[1] = rt.logicalH; v[2] = rt.canvas.width; v[3] = rt.canvas.height; },
      js_set_title: (ptr, len) => { document.title = rt.str(ptr, len); },
      js_poll_event: (ptr) => {
        const e = rt.events.shift();
        if (!e) return 0;
        const v = rt.f32(ptr, 8);
        v.fill(0);
        for (let i = 0; i < e.length && i < 8; i++) v[i] = e[i];
        return 1;
      },
      js_text_input: (on) => { rt.textInput = !!on; },
      js_relative_mouse: (on) => { if (on) rt.canvas.requestPointerLock && rt.canvas.requestPointerLock(); else if (document.exitPointerLock) document.exitPointerLock(); },
      js_cursor: (visible) => { rt.canvas.style.cursor = visible ? "default" : "none"; },
      js_audio_open: (rate, frames) => {
        try {
          const ctx = new (window.AudioContext || window.webkitAudioContext)({ sampleRate: rate });
          rt.audio = { ctx, next: 0, rate: ctx.sampleRate };
          return ctx.sampleRate;
        } catch (e) { console.warn("audio unavailable", e); return 0; }
      },
      js_audio_queue: (ptr, count) => {
        const a = rt.audio; if (!a) return;
        const frames = count / 2;
        if (frames <= 0) return;
        const buf = a.ctx.createBuffer(2, frames, a.rate);
        const src = rt.f32(ptr, count);
        const l = buf.getChannelData(0), r = buf.getChannelData(1);
        for (let i = 0; i < frames; i++) { l[i] = src[i * 2]; r[i] = src[i * 2 + 1]; }
        const node = a.ctx.createBufferSource();
        node.buffer = buf; node.connect(a.ctx.destination);
        const t = Math.max(a.next, a.ctx.currentTime + 0.02);
        node.start(t);
        a.next = t + frames / a.rate;
      },
      js_audio_queued: () => { const a = rt.audio; if (!a) return 0; return Math.max(0, Math.round((a.next - a.ctx.currentTime) * a.rate)); },
      js_gamepad_rumble: (id, low, high, ms) => {
        const gp = navigator.getGamepads()[id];
        const act = gp && (gp.vibrationActuator || (gp.hapticActuators && gp.hapticActuators[0]));
        if (act && act.playEffect) act.playEffect("dual-rumble", { duration: ms, strongMagnitude: low, weakMagnitude: high }).catch(() => {});
      },
    };
    Object.assign(eagle, this.glImports());
    return { wasi_snapshot_preview1: wasi, eagle };
  }

  wasiImports() {
    const rt = this;
    const ENOSYS = 52, EBADF = 8, ESUCCESS = 0;
    const flushLine = (fd) => {
      const key = fd === 1 ? "stdout" : "stderr";
      const lines = rt[key].split("\n");
      rt[key] = lines.pop();
      for (const line of lines) (fd === 1 ? console.log : console.warn)(line);
    };
    const base = {
      fd_write: (fd, iovs, iovsLen, nwritten) => {
        let total = 0;
        const view = rt.u32(iovs, iovsLen * 2);
        for (let i = 0; i < iovsLen; i++) {
          const ptr = view[i * 2], len = view[i * 2 + 1];
          const s = rt.str(ptr, len);
          if (fd === 1) rt.stdout += s; else rt.stderr += s;
          total += len;
        }
        rt.u32(nwritten, 1)[0] = total;
        flushLine(fd);
        return ESUCCESS;
      },
      fd_read: (fd, iovs, iovsLen, nread) => { rt.u32(nread, 1)[0] = 0; return ESUCCESS; },
      fd_close: () => ESUCCESS,
      fd_seek: (fd, offset, whence, newOffset) => { return EBADF; },
      fd_fdstat_get: (fd, ptr) => { if (fd > 2) return EBADF; const v = rt.u8(ptr, 24); v.fill(0); v[0] = 2; return ESUCCESS; },
      fd_fdstat_set_flags: () => ESUCCESS,
      fd_prestat_get: () => EBADF,
      fd_prestat_dir_name: () => EBADF,
      fd_filestat_get: () => EBADF,
      fd_readdir: () => EBADF,
      path_open: () => 76, // ENOTCAPABLE
      path_filestat_get: () => 76,
      path_unlink_file: () => 76,
      path_create_directory: () => 76,
      path_remove_directory: () => 76,
      path_rename: () => 76,
      path_readlink: () => 76,
      path_symlink: () => 76,
      environ_sizes_get: (countPtr, sizePtr) => { rt.u32(countPtr, 1)[0] = 0; rt.u32(sizePtr, 1)[0] = 0; return ESUCCESS; },
      environ_get: () => ESUCCESS,
      args_sizes_get: (countPtr, sizePtr) => { rt.u32(countPtr, 1)[0] = 1; rt.u32(sizePtr, 1)[0] = 6; return ESUCCESS; },
      args_get: (argv, buf) => { rt.u32(argv, 1)[0] = buf; rt.u8(buf, 6).set(rt.encoder.encode("eagle\0")); return ESUCCESS; },
      clock_time_get: (id, precision, ptr) => {
        const ns = id === 0 ? BigInt(Date.now()) * 1000000n : BigInt(Math.round(performance.now() * 1e6));
        new BigUint64Array(rt.mem.buffer, ptr, 1)[0] = ns;
        return ESUCCESS;
      },
      clock_res_get: (id, ptr) => { new BigUint64Array(rt.mem.buffer, ptr, 1)[0] = 1000n; return ESUCCESS; },
      random_get: (ptr, len) => { crypto.getRandomValues(rt.u8(ptr, len)); return ESUCCESS; },
      proc_exit: (code) => { rt.running = false; throw new Error("proc_exit " + code); },
      sched_yield: () => ESUCCESS,
      poll_oneoff: (inPtr, outPtr, n, neventsPtr) => { rt.u32(neventsPtr, 1)[0] = 0; return ESUCCESS; },
    };
    return new Proxy(base, { get: (t, name) => t[name] || ((...a) => { console.warn("wasi:", name, "unsupported"); return ENOSYS; }) });
  }

  initGL() {
    const opts = { antialias: !!this.options.antialias, alpha: false, depth: true, stencil: true, premultipliedAlpha: false, preserveDrawingBuffer: !!this.options.preserveDrawingBuffer };
    this.gl = this.canvas.getContext("webgl2", opts);
    if (!this.gl) throw new Error("WebGL2 is required");
  }

  glImports() {
    const rt = this;
    const O = () => rt.objects;
    const obj = id => (id ? rt.objects[id] : null);
    const add = o => { rt.objects.push(o); return rt.objects.length - 1; };
    const gen = (n, ptr, make) => { const v = rt.u32(ptr, n); for (let i = 0; i < n; i++) v[i] = add(make()); };
    const del = (n, ptr, fn) => { const v = rt.u32(ptr, n); for (let i = 0; i < n; i++) { const o = obj(v[i]); if (o) { fn(o); rt.objects[v[i]] = null; } } };
    const bytesPer = (fmt, type) => {
      const comps = ({ 0x1903: 1, 0x8227: 2, 0x1907: 3, 0x1908: 4, 0x1902: 1, 0x84F9: 1 })[fmt] || 4;
      const size = type === 0x1401 ? 1 : type === 0x1406 ? 4 : type === 0x1405 ? 4 : type === 0x84FA ? 4 : 1;
      return comps * size;
    };
    const gl = () => rt.gl;
    return {
      gl_get_error: () => gl().getError(),
      gl_get_string: (name, buf, len) => rt.writeStr(buf, len, name === 0x1F01 ? "WebGL2 (" + (gl().getParameter(gl().RENDERER) || "") + ")" : name === 0x1F02 ? "WebGL 2.0" : name === 0x8B8C ? "GLSL ES 3.00" : "web"),
      gl_get_integerv: (name, ptr) => { const v = gl().getParameter(name); rt.i32(ptr, 1)[0] = typeof v === "number" ? v : 0; },
      gl_enable: (c) => { if (c !== 0x8642 && c !== 0x0B20) gl().enable(c); },
      gl_disable: (c) => { if (c !== 0x8642 && c !== 0x0B20) gl().disable(c); },
      gl_clear: (m) => gl().clear(m),
      gl_clear_color: (r, g, b, a) => gl().clearColor(r, g, b, a),
      gl_clear_depth: (d) => gl().clearDepth(d),
      gl_clear_stencil: (s) => gl().clearStencil(s),
      gl_viewport: (x, y, w, h) => gl().viewport(x, y, w, h),
      gl_scissor: (x, y, w, h) => gl().scissor(x, y, w, h),
      gl_blend_func: (a, b) => gl().blendFunc(a, b),
      gl_blend_func_separate: (a, b, c, d) => gl().blendFuncSeparate(a, b, c, d),
      gl_blend_equation: (m) => gl().blendEquation(m),
      gl_depth_func: (f) => gl().depthFunc(f),
      gl_depth_mask: (b) => gl().depthMask(!!b),
      gl_color_mask: (r, g, b, a) => gl().colorMask(!!r, !!g, !!b, !!a),
      gl_cull_face: (m) => gl().cullFace(m),
      gl_front_face: (m) => gl().frontFace(m),
      gl_line_width: (w) => gl().lineWidth(w),
      gl_polygon_mode: () => {},
      gl_stencil_func: (f, r, m) => gl().stencilFunc(f, r, m),
      gl_stencil_op: (a, b, c) => gl().stencilOp(a, b, c),
      gl_stencil_mask: (m) => gl().stencilMask(m),
      gl_flush: () => gl().flush(),
      gl_finish: () => gl().finish(),
      gl_pixel_storei: (p, v) => gl().pixelStorei(p, v),
      gl_read_pixels: (x, y, w, h, fmt, type, ptr) => { const n = w * h * bytesPer(fmt, type); const tmp = new Uint8Array(n); gl().readPixels(x, y, w, h, fmt, type, tmp); rt.u8(ptr, n).set(tmp); },
      gl_gen_buffers: (n, ptr) => gen(n, ptr, () => gl().createBuffer()),
      gl_delete_buffers: (n, ptr) => del(n, ptr, o => gl().deleteBuffer(o)),
      gl_bind_buffer: (t, id) => gl().bindBuffer(t, obj(id)),
      gl_buffer_data: (t, size, ptr, usage) => gl().bufferData(t, rt.u8(ptr, size), usage),
      gl_buffer_sub_data: (t, off, size, ptr) => gl().bufferSubData(t, off, rt.u8(ptr, size)),
      gl_gen_vertex_arrays: (n, ptr) => gen(n, ptr, () => gl().createVertexArray()),
      gl_delete_vertex_arrays: (n, ptr) => del(n, ptr, o => gl().deleteVertexArray(o)),
      gl_bind_vertex_array: (id) => gl().bindVertexArray(obj(id)),
      gl_enable_vertex_attrib_array: (i) => gl().enableVertexAttribArray(i),
      gl_disable_vertex_attrib_array: (i) => gl().disableVertexAttribArray(i),
      gl_vertex_attrib_pointer: (i, size, type, norm, stride, off) => gl().vertexAttribPointer(i, size, type, !!norm, stride, off),
      gl_vertex_attrib_divisor: (i, d) => gl().vertexAttribDivisor(i, d),
      gl_create_shader: (t) => add(gl().createShader(t)),
      gl_shader_source: (sh, count, strings, lengths) => {
        let src = "";
        const ptrs = rt.u32(strings, count), lens = lengths ? rt.i32(lengths, count) : null;
        for (let i = 0; i < count; i++) src += lens && lens[i] >= 0 ? rt.str(ptrs[i], lens[i]) : rt.cstr(ptrs[i]);
        gl().shaderSource(obj(sh), src);
      },
      gl_compile_shader: (sh) => gl().compileShader(obj(sh)),
      gl_get_shaderiv: (sh, p, ptr) => { let v = gl().getShaderParameter(obj(sh), p); if (p === 0x8B84) v = (gl().getShaderInfoLog(obj(sh)) || "").length + 1; rt.i32(ptr, 1)[0] = typeof v === "boolean" ? (v ? 1 : 0) : v; },
      gl_get_shader_info_log: (sh, size, written, buf) => { const n = rt.writeStr(buf, size, gl().getShaderInfoLog(obj(sh)) || ""); if (written) rt.i32(written, 1)[0] = n; },
      gl_delete_shader: (sh) => { gl().deleteShader(obj(sh)); rt.objects[sh] = null; },
      gl_create_program: () => add(gl().createProgram()),
      gl_attach_shader: (p, s) => gl().attachShader(obj(p), obj(s)),
      gl_link_program: (p) => gl().linkProgram(obj(p)),
      gl_get_programiv: (p, param, ptr) => { let v = gl().getProgramParameter(obj(p), param); if (param === 0x8B84) v = (gl().getProgramInfoLog(obj(p)) || "").length + 1; rt.i32(ptr, 1)[0] = typeof v === "boolean" ? (v ? 1 : 0) : v; },
      gl_get_program_info_log: (p, size, written, buf) => { const n = rt.writeStr(buf, size, gl().getProgramInfoLog(obj(p)) || ""); if (written) rt.i32(written, 1)[0] = n; },
      gl_use_program: (p) => gl().useProgram(obj(p)),
      gl_delete_program: (p) => { gl().deleteProgram(obj(p)); rt.objects[p] = null; },
      gl_get_uniform_location: (p, name) => { const loc = gl().getUniformLocation(obj(p), rt.cstr(name)); if (!loc) return -1; rt.locations.push(loc); return rt.locations.length - 1; },
      gl_get_attrib_location: (p, name) => gl().getAttribLocation(obj(p), rt.cstr(name)),
      gl_bind_attrib_location: (p, i, name) => gl().bindAttribLocation(obj(p), i, rt.cstr(name)),
      gl_uniform1i: (l, v) => gl().uniform1i(rt.locations[l], v),
      gl_uniform1f: (l, v) => gl().uniform1f(rt.locations[l], v),
      gl_uniform2f: (l, a, b) => gl().uniform2f(rt.locations[l], a, b),
      gl_uniform3f: (l, a, b, c) => gl().uniform3f(rt.locations[l], a, b, c),
      gl_uniform4f: (l, a, b, c, d) => gl().uniform4f(rt.locations[l], a, b, c, d),
      gl_uniform1iv: (l, n, ptr) => gl().uniform1iv(rt.locations[l], rt.i32(ptr, n)),
      gl_uniform1fv: (l, n, ptr) => gl().uniform1fv(rt.locations[l], rt.f32(ptr, n)),
      gl_uniform2fv: (l, n, ptr) => gl().uniform2fv(rt.locations[l], rt.f32(ptr, n * 2)),
      gl_uniform3fv: (l, n, ptr) => gl().uniform3fv(rt.locations[l], rt.f32(ptr, n * 3)),
      gl_uniform4fv: (l, n, ptr) => gl().uniform4fv(rt.locations[l], rt.f32(ptr, n * 4)),
      gl_uniform_matrix3fv: (l, n, t, ptr) => gl().uniformMatrix3fv(rt.locations[l], !!t, rt.f32(ptr, n * 9)),
      gl_uniform_matrix4fv: (l, n, t, ptr) => gl().uniformMatrix4fv(rt.locations[l], !!t, rt.f32(ptr, n * 16)),
      gl_gen_textures: (n, ptr) => gen(n, ptr, () => gl().createTexture()),
      gl_delete_textures: (n, ptr) => del(n, ptr, o => gl().deleteTexture(o)),
      gl_bind_texture: (t, id) => gl().bindTexture(t, obj(id)),
      gl_active_texture: (u) => gl().activeTexture(u),
      gl_tex_image2d: (target, level, internal, w, h, border, fmt, type, ptr) => {
        if (ptr === 0) { gl().texImage2D(target, level, internal, w, h, border, fmt, type, null); return; }
        const n = w * h * bytesPer(fmt, type);
        const view = type === 0x1406 ? rt.f32(ptr, n / 4) : type === 0x1405 || type === 0x84FA ? rt.u32(ptr, n / 4) : rt.u8(ptr, n);
        gl().texImage2D(target, level, internal, w, h, border, fmt, type, view);
      },
      gl_tex_sub_image2d: (target, level, x, y, w, h, fmt, type, ptr) => { const n = w * h * bytesPer(fmt, type); gl().texSubImage2D(target, level, x, y, w, h, fmt, type, rt.u8(ptr, n)); },
      gl_tex_parameteri: (t, p, v) => gl().texParameteri(t, p, v),
      gl_generate_mipmap: (t) => gl().generateMipmap(t),
      gl_gen_framebuffers: (n, ptr) => gen(n, ptr, () => gl().createFramebuffer()),
      gl_delete_framebuffers: (n, ptr) => del(n, ptr, o => gl().deleteFramebuffer(o)),
      gl_bind_framebuffer: (t, id) => gl().bindFramebuffer(t, obj(id)),
      gl_framebuffer_texture2d: (t, att, tt, tex, level) => gl().framebufferTexture2D(t, att, tt, obj(tex), level),
      gl_check_framebuffer_status: (t) => gl().checkFramebufferStatus(t),
      gl_gen_renderbuffers: (n, ptr) => gen(n, ptr, () => gl().createRenderbuffer()),
      gl_delete_renderbuffers: (n, ptr) => del(n, ptr, o => gl().deleteRenderbuffer(o)),
      gl_bind_renderbuffer: (t, id) => gl().bindRenderbuffer(t, obj(id)),
      gl_renderbuffer_storage: (t, f, w, h) => gl().renderbufferStorage(t, f, w, h),
      gl_framebuffer_renderbuffer: (t, att, rt2, rb) => gl().framebufferRenderbuffer(t, att, rt2, obj(rb)),
      gl_blit_framebuffer: (a, b, c, d, e, f, g, h, mask, filter) => gl().blitFramebuffer(a, b, c, d, e, f, g, h, mask, filter),
      gl_draw_buffers: (n, ptr) => gl().drawBuffers(Array.from(rt.u32(ptr, n))),
      gl_read_buffer: (m) => gl().readBuffer(m),
      gl_draw_arrays: (m, f, c) => gl().drawArrays(m, f, c),
      gl_draw_elements: (m, c, t, off) => gl().drawElements(m, c, t, off),
      gl_draw_arrays_instanced: (m, f, c, n) => gl().drawArraysInstanced(m, f, c, n),
      gl_draw_elements_instanced: (m, c, t, off, n) => gl().drawElementsInstanced(m, c, t, off, n),
    };
  }
}
