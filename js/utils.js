// Shared browser helpers for authentication pages.
(function () {
  var ALLOWED_NEXT = {
    "dashboard.html": true,
    "login.html": true,
    "register.html": true,
    "reset-password.html": true,
    "index.html": true,
    "index-en.html": true,
    "deals.html": true,
    "deal.html": true,
    "submit-deal.html": true,
    "admin.html": true
  };

  var ALLOWED_ORIGINS = {
    "http://127.0.0.1:4173": true,
    "http://localhost:4173": true,
    "https://bundeal.de": true,
    "https://www.bundeal.de": true
  };

  var ALLOWED_CALLBACKS = {
    "login.html": true,
    "reset-password.html": true
  };

  function safeNext(value) {
    if (!value || typeof value !== "string") return "dashboard.html";
    if (value.indexOf("://") !== -1) return "dashboard.html";
    if (value.indexOf("//") === 0) return "dashboard.html";
    if (value.indexOf("\\") !== -1) return "dashboard.html";
    if (value.charAt(0) === "/") return "dashboard.html";
    if (value.indexOf("?") !== -1 || value.indexOf("#") !== -1) return "dashboard.html";
    if (!ALLOWED_NEXT[value]) return "dashboard.html";
    return value;
  }

  function callbackUrl(origin, page) {
    if (!ALLOWED_ORIGINS[origin] || !ALLOWED_CALLBACKS[page]) return "";
    return origin + "/" + page;
  }

  function safeSlug(value) {
    if (!value || typeof value !== "string") return "";
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value)) return "";
    return value;
  }

  function isAllowedOrigin(origin) {
    return !!ALLOWED_ORIGINS[origin];
  }

  function usernameError(value) {
    if (!value) return "";
    if (!/^[a-z0-9_]{3,30}$/.test(value)) return "format";
    return "";
  }

  function displayNameError(value) {
    if (!value) return "";
    if (value.length > 80) return "length";
    return "";
  }

  window.bundealUtils = {
    safeNext: safeNext,
    safeSlug: safeSlug,
    isAllowedOrigin: isAllowedOrigin,
    callbackUrl: callbackUrl,
    usernameError: usernameError,
    displayNameError: displayNameError
  };
})();
