// One header on every page. The account control stays in the same place.
(function () {
  var params = new URLSearchParams(window.location.search);
  var lang = document.documentElement.lang === "en" || params.get("lang") === "en" ? "en" : "de";
  var copy = lang === "en"
    ? {
      account: "Account", logout: "Log out", admin: "Admin", user: "User", creator: "Creator",
      menu: "Account menu", signIn: "Sign in", manage: "Admin",
      nav: "Main navigation", toGerman: "Zur deutschen Sprache", toEnglish: "Switch to English"
    }
    : {
      account: "Konto", logout: "Abmelden", admin: "Admin", user: "Nutzer", creator: "Creator",
      menu: "Kontomenü", signIn: "Anmelden", manage: "Verwaltung",
      nav: "Hauptnavigation", toGerman: "Zur deutschen Sprache", toEnglish: "Switch to English"
    };
  var items = lang === "en"
    ? [
      { key: "home", href: "index-en.html#process", label: "Process" },
      { key: "example", href: "example-en.html", label: "Example" },
      { key: "deals", href: "deals.html?lang=en", label: "Deals" },
      { key: "suggest", href: "submit-deal.html?lang=en", label: "Suggest" },
      { key: "legal", href: "legal-notice-en.html", label: "Legal notice" }
    ]
    : [
      { key: "home", href: "index.html#ablauf", label: "Ablauf" },
      { key: "example", href: "beispiel-take3.html", label: "Beispiel" },
      { key: "deals", href: "deals.html", label: "Deals" },
      { key: "suggest", href: "submit-deal.html", label: "Vorschlag" },
      { key: "legal", href: "impressum.html", label: "Impressum" }
    ];

  function client() {
    return window.bundealSupabase || null;
  }

  function fileName() {
    return (window.location.pathname.split("/").pop() || "index.html").toLowerCase();
  }

  function currentKey() {
    var file = fileName();
    if (file === "index.html" || file === "index-en.html") return "home";
    if (file === "beispiel-take3.html" || file === "example-en.html") return "example";
    if (file === "deals.html" || file === "deal.html") return "deals";
    if (file === "submit-deal.html") return "suggest";
    if (file === "impressum.html" || file === "legal-notice-en.html") return "legal";
    return "";
  }

  function pageUrl(name) {
    if (lang !== "en") return name;
    return name + (name.indexOf("?") === -1 ? "?lang=en" : "&lang=en");
  }

  function languageHref() {
    var file = fileName();
    var twins = {
      "index.html": "index-en.html",
      "index-en.html": "index.html",
      "beispiel-take3.html": "example-en.html",
      "example-en.html": "beispiel-take3.html",
      "impressum.html": "legal-notice-en.html",
      "legal-notice-en.html": "impressum.html",
      "datenschutz.html": "privacy-en.html",
      "privacy-en.html": "datenschutz.html"
    };
    if (twins[file]) return twins[file] + window.location.hash;
    var next = new URLSearchParams(window.location.search);
    if (lang === "en") next.delete("lang");
    else next.set("lang", "en");
    var query = next.toString();
    return file + (query ? "?" + query : "") + window.location.hash;
  }

  function accountName(profile, session) {
    var displayName = profile && typeof profile.display_name === "string" ? profile.display_name.trim() : "";
    var username = profile && typeof profile.username === "string" ? profile.username.trim() : "";
    if (displayName) return displayName;
    if (username) return username;
    var email = session && session.user && session.user.email ? session.user.email : "";
    return email.split("@")[0] || copy.account;
  }

  function renderNav() {
    var nav = document.querySelector(".site-nav");
    if (!nav) return;
    nav.setAttribute("aria-label", copy.nav);
    nav.replaceChildren();
    var active = currentKey();
    items.forEach(function (item) {
      var link = document.createElement("a");
      link.href = item.href;
      link.textContent = item.label;
      if (item.key === active) link.setAttribute("aria-current", "page");
      nav.appendChild(link);
    });
  }

  function languageSwitch() {
    var controls = document.querySelector(".header-controls");
    if (!controls) return null;
    var link = controls.querySelector(".language-switch");
    if (!link) {
      link = document.createElement("a");
      link.className = "language-switch";
      var toggle = controls.querySelector(".nav-toggle");
      if (toggle) controls.insertBefore(link, toggle);
      else controls.appendChild(link);
    }
    link.href = languageHref();
    link.textContent = lang === "en" ? "DE" : "EN";
    link.lang = lang === "en" ? "de" : "en";
    link.setAttribute("aria-label", lang === "en" ? copy.toGerman : copy.toEnglish);
    return link;
  }

  function slot() {
    var controls = document.querySelector(".header-controls");
    if (!controls) return null;
    var existing = controls.querySelector("[data-account-slot]");
    if (existing) return existing;
    var element = document.createElement("div");
    element.className = "account-slot";
    element.setAttribute("data-account-slot", "");
    var language = controls.querySelector(".language-switch");
    var toggle = controls.querySelector(".nav-toggle");
    controls.insertBefore(element, language || toggle || null);
    return element;
  }

  function renderSignedOut() {
    var target = slot();
    if (!target) return;
    target.replaceChildren();
    var link = document.createElement("a");
    link.className = "account-menu-button";
    link.href = pageUrl("login.html");
    link.textContent = copy.signIn;
    target.appendChild(link);
  }

  function renderSignedIn(session, profile, isAdmin, isCreator) {
    var target = slot();
    if (!target) return;
    target.replaceChildren();

    var nameText = accountName(profile, session);
    var roleText = isAdmin ? copy.admin : (isCreator ? copy.creator : copy.user);
    var root = document.createElement("div");
    root.className = "account-menu";
    root.setAttribute("data-account-menu", "");

    var button = document.createElement("button");
    button.type = "button";
    button.className = "account-menu-button";
    button.setAttribute("aria-haspopup", "menu");
    button.setAttribute("aria-expanded", "false");
    button.setAttribute("aria-label", nameText + ", " + roleText + ", " + copy.menu);

    var name = document.createElement("span");
    name.className = "account-menu-name";
    name.textContent = nameText;
    var role = document.createElement("span");
    role.className = isAdmin ? "account-role is-admin" : (isCreator ? "account-role is-creator" : "account-role");
    role.textContent = roleText;
    button.appendChild(name);
    button.appendChild(role);

    var panel = document.createElement("div");
    panel.className = "account-menu-panel";
    panel.hidden = true;
    panel.setAttribute("role", "menu");

    function addLink(href, label) {
      var item = document.createElement("a");
      item.href = href;
      item.textContent = label;
      item.setAttribute("role", "menuitem");
      panel.appendChild(item);
    }

    addLink(pageUrl("dashboard.html"), copy.account);
    if (isAdmin) addLink("admin.html", copy.manage);

    var logout = document.createElement("button");
    logout.type = "button";
    logout.textContent = copy.logout;
    logout.setAttribute("role", "menuitem");
    logout.addEventListener("click", function () {
      var api = client();
      if (!api) return;
      logout.disabled = true;
      api.auth.signOut().then(function () {
        window.location.assign(pageUrl("login.html"));
      });
    });
    panel.appendChild(logout);
    root.appendChild(button);
    root.appendChild(panel);
    target.appendChild(root);

    button.addEventListener("click", function (event) {
      event.stopPropagation();
      var open = panel.hidden;
      panel.hidden = !open;
      button.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }

  if (!window.bundealAccountMenuBound) {
    window.bundealAccountMenuBound = true;
    document.addEventListener("click", function (event) {
      var root = document.querySelector("[data-account-menu]");
      if (!root || root.contains(event.target)) return;
      var panel = root.querySelector(".account-menu-panel");
      var button = root.querySelector(".account-menu-button");
      if (panel) panel.hidden = true;
      if (button) button.setAttribute("aria-expanded", "false");
    });
    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;
      var root = document.querySelector("[data-account-menu]");
      if (!root) return;
      var panel = root.querySelector(".account-menu-panel");
      var button = root.querySelector(".account-menu-button");
      if (panel) panel.hidden = true;
      if (button) button.setAttribute("aria-expanded", "false");
    });
  }

  function refresh() {
    renderNav();
    languageSwitch();
    var api = client();
    if (!api) {
      renderSignedOut();
      return;
    }
    api.auth.getSession().then(function (result) {
      var session = result.data && result.data.session;
      if (!session) {
        renderSignedOut();
        return null;
      }
      return Promise.all([
        api.from("profiles").select("username, display_name").eq("id", session.user.id).maybeSingle(),
        api.from("user_roles").select("role").eq("user_id", session.user.id)
      ]).then(function (results) {
        var profile = results[0] && !results[0].error ? results[0].data || {} : {};
        var roles = results[1] && !results[1].error ? results[1].data || [] : [];
        var isAdmin = roles.some(function (entry) { return entry.role === "admin"; });
        var isCreator = roles.some(function (entry) { return entry.role === "creator"; });
        renderSignedIn(session, profile, isAdmin, isCreator);
      });
    }).catch(function () {
      renderSignedOut();
    });
  }

  window.bundealRefreshAccountMenu = refresh;
  refresh();
})();
