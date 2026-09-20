(() => {
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
})();
