(function () {
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.querySelector(".site-nav");

  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }

  var copyButton = document.querySelector("[data-copy-link]");
  var status = document.querySelector("[data-copy-status]");

  if (copyButton) {
    copyButton.addEventListener("click", function () {
      var url = window.location.href;

      function show(message) {
        if (status) status.textContent = message;
      }

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(function () {
          show("Link kopiert. Du kannst ihn teilen.");
        }).catch(function () {
          show(url);
        });
        return;
      }

      show(url);
    });
  }

  var suggestionForm = document.querySelector("[data-deal-suggestion]");
  var suggestionStatus = document.querySelector("[data-suggestion-status]");

  if (suggestionForm) {
    suggestionForm.addEventListener("submit", function (event) {
      event.preventDefault();

      if (!suggestionForm.reportValidity()) return;

      var data = new FormData(suggestionForm);
      var subject = "Deal-Vorschlag für BunDeal";
      var body = [
        "Link zum Angebot:",
        data.get("url"),
        "",
        "Warum ist es ein guter Deal?",
        data.get("reason"),
        "",
        "E-Mail für Rückfragen:",
        data.get("email") || "nicht angegeben"
      ].join("\n");

      if (suggestionStatus) {
        suggestionStatus.textContent = "Dein E-Mail-Programm wird geöffnet. BunDeal prüft den Vorschlag vor einer Veröffentlichung.";
      }

      window.location.href = "mailto:info@bundeal.de?subject=" +
        encodeURIComponent(subject) + "&body=" + encodeURIComponent(body);
    });
  }
})();
