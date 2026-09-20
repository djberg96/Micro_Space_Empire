(() => {
  const themes = new Set(["starfield", "nebula", "tactical", "command"]);
  let panelResizeTimer;

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

  const confirmationForms = () => {
    document.querySelectorAll("form[data-confirm]").forEach((form) => {
      if (form.dataset.bound) return;
      form.dataset.bound = "true";
      form.addEventListener("submit", (event) => {
        if (!window.confirm(form.dataset.confirm)) event.preventDefault();
      });
    });
  };

  const bindActions = () => {
    bindThemePickers();
    animateDice();
    bindPanelResizers();
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
          if (payload.html) {
            const current = document.querySelector("#game-shell");
            current.outerHTML = payload.html;
            bindActions();
            const next = document.querySelector("#game-shell");
            next.classList.add("state-enter");
            window.setTimeout(() => next.classList.remove("state-enter"), 500);
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
    panelResizeTimer = window.setTimeout(bindPanelResizers, 100);
  });
  window.addEventListener("storage", (event) => {
    if (event.key === "mse-theme" && event.newValue) applyTheme(event.newValue);
    if (event.key === "mse-dashboard-width" || event.key === "mse-action-width") bindPanelResizers();
  });
})();
