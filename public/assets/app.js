(() => {
  const themes = new Set(["starfield", "nebula", "tactical", "command"]);
  let panelResizeTimer;
  let transitionTimer;

  const applyTheme = (theme) => {
    const selected = themes.has(theme) ? theme : "starfield";
    document.documentElement.dataset.theme = selected;
    document.querySelectorAll("[data-theme-select]").forEach((picker) => {
      picker.value = selected;
    });
    try { localStorage.setItem("mse-theme", selected); } catch (_error) {}
  };

  const bindThemePickers = () => {
    const current = document.documentElement.dataset.theme || "starfield";
    document.querySelectorAll("[data-theme-select]").forEach((picker) => {
      picker.value = current;
      if (picker.dataset.bound) return;
      picker.dataset.bound = "true";
      picker.addEventListener("change", () => applyTheme(picker.value));
    });
  };

  const animateDice = () => {
    const faces = ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"];
    const reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    document.querySelectorAll("[data-die-result]").forEach((die) => {
      if (die.dataset.bound) return;
      die.dataset.bound = "true";
      const result = Number.parseInt(die.dataset.dieResult, 10);
      const face = die.querySelector("span");
      if (!face || result < 1 || result > 6 || reduceMotion) return;

      let frame = 0;
      face.textContent = faces[(result + 2) % faces.length];
      die.classList.add("is-rolling");
      const timer = window.setInterval(() => {
        face.textContent = faces[(result + frame * 3 + frame * frame) % faces.length];
        frame += 1;
        if (frame < 10) return;
        window.clearInterval(timer);
        face.textContent = faces[result - 1];
        die.classList.remove("is-rolling");
        die.classList.add("is-settled");
      }, 70);
    });
  };

  const bindPanelResizers = () => {
    const shell = document.querySelector("#game-shell");
    if (!shell) return;
    const settings = {
      dashboard: {property: "--dashboard-width", storage: "mse-dashboard-width", min: 220, max: 520},
      action: {property: "--action-width", storage: "mse-action-width", min: 280, max: 600}
    };

    const widthFor = (name) => {
      const width = Number.parseFloat(getComputedStyle(shell).getPropertyValue(settings[name].property));
      if (Number.isFinite(width)) return width;
      return name === "dashboard" ? 270 : 350;
    };
    const constrainedWidth = (name, requested) => {
      const setting = settings[name];
      const other = widthFor(name === "dashboard" ? "action" : "dashboard");
      const available = shell.clientWidth - other - 380;
      return Math.round(Math.max(setting.min, Math.min(setting.max, available, requested)));
    };
    const setWidth = (name, requested, persist = false) => {
      const setting = settings[name];
      const width = constrainedWidth(name, requested);
      shell.style.setProperty(setting.property, `${width}px`);
      const handle = shell.querySelector(`[data-panel-resizer="${name}"]`);
      if (handle) handle.setAttribute("aria-valuenow", width);
      if (persist) {
        try { localStorage.setItem(setting.storage, width); } catch (_error) {}
      }
      return width;
    };
    const resetWidth = (name) => {
      const setting = settings[name];
      shell.style.removeProperty(setting.property);
      try { localStorage.removeItem(setting.storage); } catch (_error) {}
      const handle = shell.querySelector(`[data-panel-resizer="${name}"]`);
      if (handle) handle.setAttribute("aria-valuenow", Math.round(widthFor(name)));
    };

    Object.keys(settings).forEach((name) => {
      try {
        const saved = Number.parseFloat(localStorage.getItem(settings[name].storage));
        if (Number.isFinite(saved)) setWidth(name, saved);
      } catch (_error) {}
    });

    shell.querySelectorAll("[data-panel-resizer]").forEach((handle) => {
      const name = handle.dataset.panelResizer;
      if (!settings[name]) return;
      handle.setAttribute("aria-valuenow", Math.round(widthFor(name)));
      if (getComputedStyle(handle).display === "none") return;
      if (handle.dataset.bound) return;
      handle.dataset.bound = "true";

      handle.addEventListener("pointerdown", (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        const startX = event.clientX;
        const startWidth = widthFor(name);
        const direction = name === "dashboard" ? 1 : -1;
        handle.setPointerCapture(event.pointerId);
        handle.classList.add("is-resizing");
        document.body.classList.add("resizing-panels");

        const move = (moveEvent) => setWidth(name, startWidth + (moveEvent.clientX - startX) * direction);
        const finish = (upEvent) => {
          setWidth(name, widthFor(name), true);
          handle.classList.remove("is-resizing");
          document.body.classList.remove("resizing-panels");
          if (handle.hasPointerCapture(upEvent.pointerId)) handle.releasePointerCapture(upEvent.pointerId);
          handle.removeEventListener("pointermove", move);
          handle.removeEventListener("pointerup", finish);
          handle.removeEventListener("pointercancel", finish);
        };
        handle.addEventListener("pointermove", move);
        handle.addEventListener("pointerup", finish);
        handle.addEventListener("pointercancel", finish);
      });

      handle.addEventListener("keydown", (event) => {
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
        event.preventDefault();
        const visualDelta = (event.key === "ArrowRight" ? 1 : -1) * (event.shiftKey ? 40 : 12);
        const direction = name === "dashboard" ? 1 : -1;
        setWidth(name, widthFor(name) + visualDelta * direction, true);
      });
      handle.addEventListener("dblclick", () => resetWidth(name));
    });
  };

  const bindEmpireZoom = () => {
    const shell = document.querySelector("#game-shell");
    const grid = shell?.querySelector(".empire-section .card-grid");
    if (!shell || !grid) return;
    const levels = [60, 80, 100, 125, 150, 175, 200];
    let zoom = 100;
    try {
      const saved = Number.parseInt(localStorage.getItem("mse-empire-zoom"), 10);
      if (levels.includes(saved)) zoom = saved;
    } catch (_error) {}

    const applyZoom = (requested, persist = false) => {
      zoom = levels.includes(requested) ? requested : 100;
      const largeBoard = window.matchMedia("(min-width: 1800px) and (min-height: 1000px)").matches;
      const fullBoard = window.matchMedia("(min-width: 1100px) and (min-height: 750px)").matches;
      const baseSize = largeBoard ? 190 : (fullBoard ? 150 : 160);
      grid.style.setProperty("--empire-card-size", `${Math.round(baseSize * zoom / 100)}px`);
      shell.querySelectorAll("[data-empire-zoom-value]").forEach((output) => { output.textContent = `${zoom}%`; });
      const index = levels.indexOf(zoom);
      const out = shell.querySelector("[data-empire-zoom=out]");
      const into = shell.querySelector("[data-empire-zoom=in]");
      if (out) out.disabled = index === 0;
      if (into) into.disabled = index === levels.length - 1;
      if (persist) {
        try { localStorage.setItem("mse-empire-zoom", zoom); } catch (_error) {}
      }
    };

    applyZoom(zoom);
    shell.querySelectorAll("[data-empire-zoom]").forEach((button) => {
      if (button.dataset.bound) return;
      button.dataset.bound = "true";
      button.addEventListener("click", () => {
        const action = button.dataset.empireZoom;
        const index = levels.indexOf(zoom);
        if (action === "out" && index > 0) applyZoom(levels[index - 1], true);
        if (action === "in" && index < levels.length - 1) applyZoom(levels[index + 1], true);
        if (action === "reset") applyZoom(100, true);
      });
    });
  };

  const confirmationForms = () => {
    document.querySelectorAll("form").forEach((form) => {
      if (form.dataset.confirmBound) return;
      form.dataset.confirmBound = "true";
      form.addEventListener("submit", (event) => {
        const message = event.submitter?.dataset.confirm || form.dataset.confirm;
        if (message && !window.confirm(message)) event.preventDefault();
      });
    });
  };

  const morphKey = (node) => {
    if (node.nodeType !== Node.ELEMENT_NODE) return null;
    return node.getAttribute("data-morph-key") || (node.id ? `id:${node.id}` : null);
  };

  const compatibleNodes = (current, incoming) => {
    if (current.nodeType !== incoming.nodeType) return false;
    if (current.nodeType !== Node.ELEMENT_NODE) return true;
    const currentKey = morphKey(current);
    const incomingKey = morphKey(incoming);
    if (currentKey || incomingKey) return currentKey === incomingKey;
    return current.tagName === incoming.tagName;
  };

  const syncAttributes = (current, incoming) => {
    const runtimeAttributes = new Set(["data-bound", "data-confirm-bound"]);
    Array.from(current.attributes).forEach(({name}) => {
      if (!incoming.hasAttribute(name) && !runtimeAttributes.has(name)) current.removeAttribute(name);
    });
    Array.from(incoming.attributes).forEach(({name, value}) => {
      if (current.getAttribute(name) !== value) current.setAttribute(name, value);
    });
  };

  const morphNode = (current, incoming) => {
    if (!compatibleNodes(current, incoming)) {
      current.replaceWith(incoming);
      return incoming;
    }

    if (current.nodeType === Node.TEXT_NODE || current.nodeType === Node.COMMENT_NODE) {
      if (current.nodeValue !== incoming.nodeValue) current.nodeValue = incoming.nodeValue;
      return current;
    }

    syncAttributes(current, incoming);
    morphChildren(current, incoming);

    if (current instanceof HTMLInputElement) {
      if (current.type === "checkbox" || current.type === "radio") current.checked = incoming.checked;
      else if (current.value !== incoming.value) current.value = incoming.value;
    } else if (current instanceof HTMLSelectElement && current.value !== incoming.value) {
      current.value = incoming.value;
    }
    return current;
  };

  const morphChildren = (current, incoming) => {
    const incomingChildren = Array.from(incoming.childNodes);
    let cursor = current.firstChild;

    incomingChildren.forEach((incomingChild) => {
      const key = morphKey(incomingChild);
      let match = null;

      if (key) {
        match = Array.from(current.childNodes).find((candidate) => morphKey(candidate) === key) || null;
      } else if (cursor && !morphKey(cursor) && compatibleNodes(cursor, incomingChild)) {
        match = cursor;
      }

      if (!match) {
        current.insertBefore(incomingChild, cursor);
        cursor = incomingChild.nextSibling;
        return;
      }

      if (match !== cursor) current.insertBefore(match, cursor);
      const morphed = morphNode(match, incomingChild);
      cursor = morphed.nextSibling;
    });

    while (cursor) {
      const next = cursor.nextSibling;
      cursor.remove();
      cursor = next;
    }
  };

  const updateGameShell = (html) => {
    const template = document.createElement("template");
    template.innerHTML = html.trim();
    const incoming = template.content.querySelector("#game-shell");
    const current = document.querySelector("#game-shell");
    if (!current || !incoming) return false;
    morphNode(current, incoming);
    return true;
  };

  const bindActions = () => {
    bindThemePickers();
    animateDice();
    bindPanelResizers();
    bindEmpireZoom();
    confirmationForms();
    document.querySelectorAll("form.async-action").forEach((form) => {
      if (form.dataset.bound) return;
      form.dataset.bound = "true";
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const actionUrl = form.getAttribute("action");
        if (!actionUrl) return;
        const button = form.querySelector("button[type=submit], button:not([type])");
        if (button) button.disabled = true;
        try {
          const response = await fetch(actionUrl, {
            method: "POST",
            body: new FormData(form),
            headers: {"X-Requested-With": "fetch", "Accept": "application/json"},
            credentials: "same-origin"
          });
          const payload = await response.json();
          if (payload.html && updateGameShell(payload.html)) {
            bindActions();
            const transition = document.querySelector("#game-shell .transition-message");
            if (transition) {
              window.clearTimeout(transitionTimer);
              transition.classList.add("is-new");
              transitionTimer = window.setTimeout(() => transition.classList.remove("is-new"), 1100);
            }
          } else if (payload.html) {
            window.location.reload();
          }
        } catch (_error) {
          window.location.reload();
        }
      });
    });
  };

  document.addEventListener("DOMContentLoaded", bindActions);
  window.addEventListener("resize", () => {
    window.clearTimeout(panelResizeTimer);
    panelResizeTimer = window.setTimeout(() => {
      bindPanelResizers();
      bindEmpireZoom();
    }, 100);
  });
  window.addEventListener("storage", (event) => {
    if (event.key === "mse-theme" && event.newValue) applyTheme(event.newValue);
    if (event.key === "mse-dashboard-width" || event.key === "mse-action-width") bindPanelResizers();
    if (event.key === "mse-empire-zoom") bindEmpireZoom();
  });
})();
