// The script's world, set up once before the script runs: `tools`, `inputs`, `text`, `console`,
// timers and `exit`, and nothing else. Every effect goes through the native `__native_host`
// function, which enforces the limits; this file only gives it a friendly shape. The script can
// tamper with built-ins after this runs, but that only breaks its own run: the host checks every
// request.
(() => {
  "use strict";
  const host = globalThis.__native_host;
  delete globalThis.__native_host;
  const { stringify, parse } = JSON;
  const SCRIPT = "script.js";

  /** Failure kinds the bridge attaches to errors it throws, such as hitting the output limit. */
  const kinds = new WeakMap();
  /** Where in the script an error was thrown, or where the tool call it reports was made. */
  const positions = new WeakMap();

  function request(op) {
    const reply = parse(host(stringify(op)));
    if (Object.hasOwn(reply, "error")) {
      const error = new TypeError(reply.error);
      if (reply.kind) kinds.set(error, reply.kind);
      throw error;
    }
    return reply.value;
  }

  Object.defineProperty(Error, "prepareStackTrace", {
    writable: false,
    configurable: false,
    value(error, frames) {
      const own = frames.filter((frame) => frame.getFileName() === SCRIPT);
      const top = own[0];
      if (top && top.getLineNumber() !== null && !positions.has(error)) {
        positions.set(error, { line: top.getLineNumber(), column: top.getColumnNumber() });
      }
      return [String(error), ...own.map((frame) => `    at ${frame}`)].join("\n");
    },
  });

  function positionOf(error) {
    if (error === null || (typeof error !== "object" && typeof error !== "function")) return undefined;
    try {
      void error.stack; // Formatting the stack records the position.
    } catch {}
    return positions.get(error);
  }

  function describe(error) {
    try {
      return String(error);
    } catch {
      return "The script threw a value that can't be described";
    }
  }

  function fail(error) {
    const failure = { kind: kinds.get(error) ?? "exception", message: describe(error), ...positionOf(error) };
    request({ op: "fail", failure });
  }

  const { bindings, inputs: suppliedInputs } = request({ op: "metadata" });

  // Tools ------------------------------------------------------------------------------------

  const pending = new Map();

  function callTool(index, label, input) {
    if (input === undefined) input = {};
    if (input === null || typeof input !== "object" || Array.isArray(input)) {
      throw new TypeError(`${label} takes one object argument`);
    }
    const site = new Error();
    positionOf(site);
    const position = positions.get(site);
    // The host shows where a call was made, such as when it asks the user to approve it.
    const id = request({ op: "call", index, input, ...position });
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject, label, position });
    });
  }

  /** A namespace object that names what exists when the script asks for something that doesn't. */
  function namespace(prefix) {
    const target = Object.create(null);
    return {
      target,
      proxy: new Proxy(target, {
        get(target, key) {
          if (typeof key !== "string" || Object.hasOwn(target, key)) return target[key];
          if (key === "then" || key === "toJSON") return undefined;
          const known = Object.keys(target).join(", ") || "none";
          throw new TypeError(`${prefix}.${key} doesn't exist. Available here: ${known}`);
        },
        set() {
          throw new TypeError(`${prefix} is read-only`);
        },
      }),
    };
  }

  const root = namespace("tools");
  const namespaces = new Map([["", root]]);
  bindings.forEach(({ path }, index) => {
    let parent = root;
    for (let depth = 1; depth < path.length; depth++) {
      const key = path.slice(0, depth).join(".");
      let child = namespaces.get(key);
      if (!child) {
        child = namespace(`tools.${key}`);
        namespaces.set(key, child);
        parent.target[path[depth - 1]] = child.proxy;
      }
      parent = child;
    }
    const label = `tools.${path.join(".")}`;
    parent.target[path[path.length - 1]] = (input) => callTool(index, label, input);
  });

  // Inputs -----------------------------------------------------------------------------------

  const inputValues = Object.freeze(Object.assign(Object.create(null), suppliedInputs));
  const inputs = new Proxy(inputValues, {
    get(target, key) {
      if (typeof key !== "string" || Object.hasOwn(target, key)) return target[key];
      if (key === "then" || key === "toJSON") return undefined;
      const known = Object.keys(target).join(", ") || "none";
      throw new ReferenceError(`inputs.${key} wasn't supplied. Inputs for this run: ${known}`);
    },
  });

  // Output -----------------------------------------------------------------------------------

  function render(value) {
    if (typeof value === "string") return value;
    if (value instanceof Error) return describe(value);
    try {
      return stringify(value) ?? String(value);
    } catch {
      return describe(value);
    }
  }

  function text(...values) {
    request({ op: "text", text: values.map(render).join(" ") });
  }

  // Timers -----------------------------------------------------------------------------------

  const timers = new Map();

  function schedule(callback, delay, repeat, args) {
    if (typeof callback !== "function") throw new TypeError("Timers take a function");
    const id = request({ op: "schedule", delay: Number(delay ?? 0), repeat });
    timers.set(id, { callback, args, repeat });
    return id;
  }

  function clear(id) {
    if (!timers.has(id)) return;
    timers.delete(id);
    request({ op: "clear", id });
  }

  // Globals ----------------------------------------------------------------------------------

  const console = Object.freeze({ log: text, info: text, warn: text, error: text, debug: text });
  const constant = (value) => ({ value, enumerable: true });
  Object.defineProperties(globalThis, {
    tools: constant(root.proxy),
    inputs: constant(inputs),
    text: constant(text),
    console: constant(console),
    setTimeout: constant((callback, delay, ...args) => schedule(callback, delay, false, args)),
    setInterval: constant((callback, delay, ...args) => schedule(callback, delay, true, args)),
    clearTimeout: constant(clear),
    clearInterval: constant(clear),
    exit: constant(() => request({ op: "exit" })),
    require: {
      value() {
        throw new TypeError(
          "require isn't available: scripts have no modules, files, network or processes. " +
            "Call tools.<path>() for anything outside the script; Object.keys(tools) lists them."
        );
      },
    },
  });

  // What the runtime calls -------------------------------------------------------------------

  globalThis.__native_guest = [
    // The script's evaluation promise.
    (evaluation) => {
      Promise.resolve(evaluation).then(() => request({ op: "complete" }), fail);
    },
    // A tool result, its content as JSON text.
    (id, isError, contentJSON) => {
      const waiter = pending.get(id);
      pending.delete(id);
      const content = parse(contentJSON);
      if (!isError) return waiter.resolve(content);
      const detail = typeof content === "string" ? content : stringify(content);
      const error = new Error(`${waiter.label} failed: ${detail}`);
      if (waiter.position) positions.set(error, waiter.position);
      waiter.reject(error);
    },
    // A timer that's due.
    (id) => {
      const timer = timers.get(id);
      if (!timer) return;
      if (!timer.repeat) timers.delete(id);
      try {
        timer.callback(...timer.args);
      } catch (error) {
        fail(error);
      }
    },
  ];
})();
