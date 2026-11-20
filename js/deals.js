// Public deal list, deal detail and suggestion form. No affiliate URL is read here.
(function () {
  var utils = window.bundealUtils || {};
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  var page = document.body.getAttribute("data-page");
  var copy = {
    de: {
      proto: "Prototyp. Ein Kauf ist über BunDeal noch nicht als Auszahlung möglich.",
      listTitle: "Freigeschaltete Angebote",
      listLead: "Der Händlerpreis ist der Preis im Shop. Cashback ist eine spätere Zahlung von BunDeal aus bestätigter Provision.",
      navSuggest: "Vorschlag",
      navLogin: "Anmelden",
      submitLead: "BunDeal prüft den Vorschlag. Er wird nicht automatisch veröffentlicht.",
      submitButton: "Vorschlag speichern",
      fieldTitle: "Titel",
      fieldDescription: "Beschreibung",
      fieldUrl: "https-Link",
      fieldPrice: "Preis in Cent, optional",
      missing: "Die Deal-Liste ist in dieser öffentlichen Vorschau noch nicht angebunden.",
      empty: "Es ist noch kein freigeschalteter Deal vorhanden.",
      loadFailed: "Die Deals konnten nicht geladen werden.",
      priceLabel: "Du zahlst beim Händler",
      estimateNote: "Cashback entsteht erst aus bestätigter Provision. Ein angezeigter Schätzwert ist kein Versprechen.",
      loginToBuy: "Einloggen und zum Händler",
      buy: "Zum Händler",
      suggest: "Deal vorschlagen",
      saved: "Der Vorschlag ist gespeichert und wird geprüft.",
      saveFailed: "Der Vorschlag konnte nicht gespeichert werden.",
      invalid: "Bitte Titel, Beschreibung und eine https-Adresse prüfen.",
      ownPending: "Deine offenen Vorschläge",
      noPending: "Du hast keinen offenen Vorschlag."
    },
    en: {
      proto: "Prototype. A purchase through BunDeal is not yet a payout.",
      listTitle: "Published offers",
      listLead: "The merchant price is the shop price. Cashback is a later BunDeal payment from confirmed commission.",
      navSuggest: "Suggest",
      navLogin: "Sign in",
      submitLead: "BunDeal reviews the suggestion. It is not published automatically.",
      submitButton: "Save suggestion",
      fieldTitle: "Title",
      fieldDescription: "Description",
      fieldUrl: "https link",
      fieldPrice: "Price in cents, optional",
      missing: "The deal list is not connected in this public preview yet.",
      empty: "No published deal is available yet.",
      loadFailed: "The deals could not be loaded.",
      priceLabel: "You pay the merchant",
      estimateNote: "Cashback comes only from confirmed commission. A shown estimate is not a promise.",
      loginToBuy: "Sign in and continue to the merchant",
      buy: "Continue to the merchant",
      suggest: "Suggest a deal",
      saved: "The suggestion is saved and will be reviewed.",
      saveFailed: "The suggestion could not be saved.",
      invalid: "Check the title, description and an https address.",
      ownPending: "Your open suggestions",
      noPending: "You have no open suggestion."
    }
  };

  function t(key) {
    return (copy[lang] && copy[lang][key]) || key;
  }

  function applyI18n() {
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach(function (element) {
      element.textContent = t(element.getAttribute("data-i18n"));
    });
    var languageSwitch = document.querySelector("[data-language-switch]");
    var current = window.location.pathname.split("/").pop() || "deals.html";
    var slug = utils.safeSlug ? utils.safeSlug(params.get("slug")) : "";
    var ref = params.get("ref") || "";
    var campaign = params.get("c") || "";
    if (!/^[a-z0-9]{10}$/.test(ref)) ref = "";
    if (!/^[a-z0-9]{10}$/.test(campaign)) campaign = "";
    var query = "";
    if (slug) query += "slug=" + encodeURIComponent(slug) + "&";
    if (ref) query += "ref=" + encodeURIComponent(ref) + "&";
    if (campaign) query += "c=" + encodeURIComponent(campaign) + "&";
    if (languageSwitch) {
      if (lang === "en") {
        languageSwitch.textContent = "DE";
        languageSwitch.href = current + (query ? "?" + query.slice(0, -1) : "");
        languageSwitch.lang = "de";
      } else {
        languageSwitch.textContent = "EN";
        languageSwitch.href = current + "?" + query + "lang=en";
        languageSwitch.lang = "en";
      }
    }
  }

  function client() {
    return window.bundealSupabase || null;
  }

  function setStatus(message, isError) {
    var element = document.querySelector("[data-deal-status]");
    if (!element) return;
    element.textContent = message || "";
    element.className = isError ? "form-error" : "status";
  }

  function formatMoney(cents, currency) {
    var amount = Number(cents);
    if (!Number.isFinite(amount)) return "";
    var negative = amount < 0;
    var absolute = Math.abs(Math.trunc(amount));
    var major = Math.floor(absolute / 100);
    var minor = absolute % 100;
    var text = (negative ? "-" : "") + major + "," + (minor < 10 ? "0" : "") + minor;
    return currency === "EUR" ? text + " €" : text + " " + currency;
  }

  function safeImage(url) {
    return typeof url === "string" && /^https:\/\/[^\s<>"'@#]+$/.test(url) && url.length <= 1000;
  }

  function renderList(rows) {
    var target = document.querySelector("[data-deal-list]");
    if (!target) return;
    target.replaceChildren();
    if (!rows.length) {
      var empty = document.createElement("p");
      empty.textContent = t("empty");
      target.appendChild(empty);
      return;
    }
    rows.forEach(function (deal) {
      var article = document.createElement("article");
      article.className = "card";
      var title = document.createElement("h3");
      var link = document.createElement("a");
      var href = "deal.html?slug=" + encodeURIComponent(deal.slug);
      link.href = lang === "en" ? href + "&lang=en" : href;
      link.textContent = deal.title;
      title.appendChild(link);
      var merchant = document.createElement("p");
      merchant.textContent = deal.merchant_name || "";
      var price = document.createElement("p");
      price.textContent = formatMoney(deal.current_price_cents, deal.currency);
      article.appendChild(title);
      article.appendChild(merchant);
      article.appendChild(price);
      target.appendChild(article);
    });
  }

  function loadList() {
    if (!client()) {
      setStatus(t("missing"), true);
      return;
    }
    client().from("public_deals").select("slug,title,merchant_name,current_price_cents,currency").order("published_at", { ascending: false }).then(function (result) {
      if (result.error) {
        setStatus(t("loadFailed"), true);
        return;
      }
      renderList(result.data || []);
    });
  }

  function renderDetail(deal) {
    document.querySelector("[data-deal-title]").textContent = deal.title;
    document.querySelector("[data-deal-merchant]").textContent = deal.merchant_name || "";
    document.querySelector("[data-deal-description]").textContent = deal.description;
    document.querySelector("[data-deal-price]").textContent = formatMoney(deal.current_price_cents, deal.currency);
    var estimate = document.querySelector("[data-deal-estimate]");
    estimate.textContent = deal.cashback_estimate_label ? deal.cashback_estimate_label + " " + t("estimateNote") : t("estimateNote");
    var image = document.querySelector("[data-deal-image]");
    if (image && safeImage(deal.product_image_url)) {
      image.src = deal.product_image_url;
      image.alt = deal.title;
      image.hidden = false;
    }
  }

  function loadDetail() {
    var slug = utils.safeSlug ? utils.safeSlug(params.get("slug")) : "";
    if (!slug) {
      setStatus(t("loadFailed"), true);
      return;
    }
    if (!client()) {
      setStatus(t("missing"), true);
      return;
    }
    client().from("public_deals").select("slug,title,description,merchant_name,current_price_cents,currency,cashback_estimate_label,product_image_url").eq("slug", slug).maybeSingle().then(function (result) {
      if (result.error || !result.data) {
        setStatus(t("loadFailed"), true);
        return;
      }
      renderDetail(result.data);
    });
  }

  function loadOwnSubmissions() {
    var list = document.querySelector("[data-own-submissions]");
    if (!list || !client()) return;
    client().auth.getSession().then(function (sessionResult) {
      var session = sessionResult.data.session;
      if (!session) return;
      return client().from("deal_submissions").select("proposed_title,submission_status").eq("submitted_by", session.user.id).eq("submission_status", "pending");
    }).then(function (result) {
      if (!result || result.error) return;
      list.replaceChildren();
      var heading = document.createElement("h2");
      heading.textContent = t("ownPending");
      list.appendChild(heading);
      if (!result.data.length) {
        var empty = document.createElement("p");
        empty.textContent = t("noPending");
        list.appendChild(empty);
        return;
      }
      result.data.forEach(function (row) {
        var item = document.createElement("p");
        item.textContent = row.proposed_title;
        list.appendChild(item);
      });
    });
  }

  function bindSubmit() {
    var form = document.querySelector("[data-suggestion-form]");
    if (!form) return;
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (!client()) {
        setStatus(t("missing"), true);
        return;
      }
      var title = form.title.value.trim();
      var description = form.description.value.trim();
      var url = form.url.value.trim();
      var priceText = form.price.value.trim();
      var price = priceText ? Number(priceText) : null;
      if (title.length < 3 || description.length < 10 || !/^https:\/\/[^\s<>"'@#]+$/.test(url) || (priceText && (!Number.isInteger(price) || price < 0))) {
        setStatus(t("invalid"), true);
        return;
      }
      client().auth.getSession().then(function (sessionResult) {
        if (!sessionResult.data.session) {
          window.location.assign("login.html?next=submit-deal.html" + (lang === "en" ? "&lang=en" : ""));
          return null;
        }
        return client().from("deal_submissions").insert({
          proposed_title: title,
          proposed_description: description,
          proposed_url: url,
          proposed_price_cents: price,
          currency: "EUR"
        });
      }).then(function (result) {
        if (!result) return;
        if (result.error) {
          setStatus(t("saveFailed"), true);
          return;
        }
        form.reset();
        setStatus(t("saved"), false);
        loadOwnSubmissions();
      });
    });
  }

  applyI18n();
  if (page === "deals") loadList();
  if (page === "deal") loadDetail();
  if (page === "submit") {
    bindSubmit();
    loadOwnSubmissions();
  }
})();
