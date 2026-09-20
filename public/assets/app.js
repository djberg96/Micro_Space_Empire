(() => {
  const themes = new Set(["starfield", "nebula", "tactical", "command"]);

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
    confirmationForms();
    document.querySelectorAll("form.async-action").forEach((form) => {
      if (form.dataset.bound) return;
      form.dataset.bound = "true";
      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const button = form.querySelector("button[type=submit], button:not([type])");
        if (button) button.disabled = true;
        try {
          const response = await fetch(form.action, {
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
  window.addEventListener("storage", (event) => {
    if (event.key === "mse-theme" && event.newValue) applyTheme(event.newValue);
  });
})();
