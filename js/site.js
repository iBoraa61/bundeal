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

  if (!copyButton) return;

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
})();
