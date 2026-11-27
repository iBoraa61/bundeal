// Public deal list, deal detail and suggestion form. No affiliate URL is read here.
(function () {
  var utils = window.bundealUtils || {};
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" || document.documentElement.lang === "en" ? "en" : "de";
  var page = document.body.getAttribute("data-page");
  var copy = {
    de: {
      proto: "Kauf noch nicht möglich. Die Angebote sind Beispiele, eine Auszahlung ist nicht freigeschaltet.",
      listTitle: "Angebote",
      listLead: "Der Händlerpreis ist der Preis im Shop. Cashback ist eine spätere Zahlung von BunDeal aus bestätigter Provision.",
      emptyTitle: "Die ersten Angebote folgen.",
      emptyBody: "Jedes Angebot zeigt, was dazu gehört: ein Deal ohne Cashback, nur Cashback, Cashback mit Empfehlung, oder zusätzlich eine Creator-Kampagne.",
      noHitsTitle: "Keine Treffer",
      noHitsBody: "Suchbegriff, Kategorie, Art oder Händler ändern.",
      filterSearch: "Suche",
      filterAll: "Alle",
      filterMode: "Art",
      filterMerchant: "Händler",
      wasPrice: "Vorheriger Shop-Preis",
      shopCut: "im Shop",
      temperature: "Temperatur",
      comments: "Kommentare",
      modeListing: "Deal",
      modeCashback: "Cashback",
      modeReferral: "Empfehlung",
      modeCreator: "Creator",
      benefitListing: "Kein Cashback auf diesem Angebot",
      benefitCashback: "Sparen über Cashback",
      benefitReferral: "Sparen über Cashback und Weiterempfehlung",
      benefitCreator: "Sparen über Cashback, Weiterempfehlung und Creator",
      estimateShort: "Schätzwert, kein Versprechen",
      noteListing: "Nur der Preis beim Händler. BunDeal zahlt hier kein Cashback.",
      noteCashback: "Nur Käufer-Cashback. Einen persönlichen Empfehlungslink gibt es hier nicht.",
      noteReferral: "Cashback für den Käufer. Nach dem eigenen Kauf kann ein persönlicher Link geteilt werden.",
      noteCreator: "Cashback, Empfehlung und eine Creator-Kampagne sind möglich.",
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
      loading: "Angebote werden geladen.",
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
      proto: "Purchase is not possible yet. The offers are examples, and no payout is enabled.",
      listTitle: "Offers",
      listLead: "The merchant price is the shop price. Cashback is a later BunDeal payment from confirmed commission.",
      emptyTitle: "The first offers are on the way.",
      emptyBody: "Each offer shows what it includes: a deal without cashback, cashback only, cashback with a referral, or a creator campaign as well.",
      noHitsTitle: "No matches",
      noHitsBody: "Change the search, category, type or merchant.",
      filterSearch: "Search",
      filterAll: "All",
      filterMode: "Type",
      filterMerchant: "Merchant",
      wasPrice: "Previous shop price",
      shopCut: "in the shop",
      temperature: "Temperature",
      comments: "Comments",
      modeListing: "Deal",
      modeCashback: "Cashback",
      modeReferral: "Referral",
      modeCreator: "Creator",
      benefitListing: "No cashback on this offer",
      benefitCashback: "Save through cashback",
      benefitReferral: "Save through cashback and a referral",
      benefitCreator: "Save through cashback, a referral and a creator campaign",
      estimateShort: "Estimate, not a promise",
      noteListing: "Shop price only. BunDeal does not pay cashback on this offer.",
      noteCashback: "Buyer cashback only. There is no personal referral link on this offer.",
      noteReferral: "Cashback for the buyer. After your own purchase you can share a personal link.",
      noteCreator: "Cashback, a referral and a creator campaign are possible.",
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
      loading: "Loading offers.",
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

  function offerMode(value) {
    if (value === "listing" || value === "cashback" || value === "creator") return value;
    return "referral";
  }

  function offerLabel(value) {
    var mode = offerMode(value);
    if (mode === "listing") return t("modeListing");
    if (mode === "cashback") return t("modeCashback");
    if (mode === "creator") return t("modeCreator");
    return t("modeReferral");
  }

  function offerNote(value) {
    var mode = offerMode(value);
    if (mode === "listing") return t("noteListing");
    if (mode === "cashback") return t("noteCashback");
    if (mode === "creator") return t("noteCreator");
    return t("noteReferral");
  }

  function offerBadge(value) {
    var mode = offerMode(value);
    var badge = document.createElement("span");
    badge.className = "offer-pill is-" + mode;
    badge.textContent = offerLabel(mode);
    return badge;
  }

  function offerBenefit(value) {
    var mode = offerMode(value);
    if (mode === "listing") return t("benefitListing");
    if (mode === "cashback") return t("benefitCashback");
    if (mode === "creator") return t("benefitCreator");
    return t("benefitReferral");
  }

  function excerpt(value) {
    var text = typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
    if (text.length <= 160) return text;
    return text.slice(0, 157).trim() + "…";
  }

  function estimateLabel(value) {
    var text = typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
    if (!text || text.length > 80) return "";
    return text;
  }

  function shopCut(deal) {
    var original = Number(deal.original_price_cents);
    var current = Number(deal.current_price_cents);
    if (!Number.isFinite(original) || !Number.isFinite(current)) return null;
    original = Math.trunc(original);
    current = Math.trunc(current);
    if (original <= current || original <= 0) return null;
    return { original: original, percent: Math.floor((original - current) * 100 / original) };
  }

  function priceStack(deal) {
    var block = document.createElement("div");
    var priceLabel = document.createElement("p");
    priceLabel.className = "deal-price-label";
    priceLabel.textContent = t("priceLabel");
    var price = document.createElement("p");
    price.className = "deal-price";
    price.textContent = formatMoney(deal.current_price_cents, deal.currency);
    block.appendChild(priceLabel);
    block.appendChild(price);
    var cut = shopCut(deal);
    if (cut) {
      var was = document.createElement("p");
      was.className = "deal-was";
      var old = document.createElement("s");
      old.textContent = formatMoney(cut.original, deal.currency);
      was.appendChild(old);
      was.appendChild(document.createTextNode(" " + t("wasPrice") + " · −" + cut.percent + " % " + t("shopCut")));
      block.appendChild(was);
    }
    return block;
  }

  function dealMedia(deal, mode) {
    var media = document.createElement("div");
    media.className = "deal-media is-" + mode;
    if (safeImage(deal.product_image_url)) {
      var image = document.createElement("img");
      image.src = deal.product_image_url;
      image.alt = "";
      media.appendChild(image);
    } else {
      media.classList.add("is-empty");
    }
    return media;
  }

  function renderList(rows, kind) {
    var target = document.querySelector("[data-deal-list]");
    if (!target) return;
    target.replaceChildren();
    target.removeAttribute("aria-busy");
    if (!rows.length) {
      var empty = document.createElement("article");
      empty.className = "empty-market";
      var title = document.createElement("h2");
      var body = document.createElement("p");
      if (kind === "filter") {
        title.textContent = t("noHitsTitle");
        body.textContent = t("noHitsBody");
      } else if (kind === "offline") {
        title.textContent = t("emptyTitle");
        body.textContent = t("missing");
      } else if (kind === "error") {
        title.textContent = t("loadFailed");
        body.textContent = t("empty");
      } else {
        title.textContent = t("emptyTitle");
        body.textContent = t("emptyBody");
      }
      empty.appendChild(title);
      empty.appendChild(body);
      target.appendChild(empty);
      return;
    }
    rows.forEach(function (deal) {
      var mode = offerMode(deal.offer_mode);
      var article = document.createElement("article");
      article.className = "deal-card is-" + mode;
      var href = "deal.html?slug=" + encodeURIComponent(deal.slug);
      if (lang === "en") href += "&lang=en";
      var link = document.createElement("a");
      link.href = href;
      link.appendChild(dealMedia(deal, mode));
      var body = document.createElement("div");
      body.className = "deal-body";
      var kicker = document.createElement("div");
      kicker.className = "deal-kicker";
      var merchant = document.createElement("p");
      merchant.className = "deal-merchant";
      merchant.textContent = [deal.merchant_name, deal.category_name].filter(Boolean).join(" · ");
      kicker.appendChild(merchant);
      kicker.appendChild(offerBadge(mode));
      var title = document.createElement("h3");
      title.textContent = deal.title;
      var summary = document.createElement("p");
      summary.className = "deal-excerpt";
      summary.textContent = excerpt(deal.description);
      var foot = document.createElement("div");
      foot.className = "deal-foot";
      var priceBlock = priceStack(deal);
      var saving = document.createElement("p");
      saving.className = "deal-benefit";
      var shownEstimate = estimateLabel(deal.cashback_estimate_label);
      saving.textContent = mode === "listing" || !shownEstimate ? offerBenefit(mode) : offerBenefit(mode) + " · " + t("estimateShort") + ": " + shownEstimate;
      foot.appendChild(priceBlock);
      foot.appendChild(saving);
      if (deal.temperature_score !== undefined && deal.temperature_score !== null) {
        var meta = document.createElement("p");
        meta.className = "fine";
        meta.textContent = t("temperature") + " " + deal.temperature_score + " · " + t("comments") + " " + (deal.comment_count || 0);
        foot.appendChild(meta);
      }
      body.appendChild(kicker);
      body.appendChild(title);
      if (summary.textContent) body.appendChild(summary);
      body.appendChild(foot);
      link.appendChild(body);
      article.appendChild(link);
      target.appendChild(article);
    });
  }

  var catalog = [];
  var filters = { q: "", category: "", mode: "", merchant: "" };

  function renderLoading() {
    var target = document.querySelector("[data-deal-list]");
    if (!target) return;
    target.replaceChildren();
    target.setAttribute("aria-busy", "true");
    [0, 1].forEach(function () {
      var card = document.createElement("article");
      card.className = "deal-card is-loading";
      var media = document.createElement("div");
      media.className = "deal-media";
      var body = document.createElement("div");
      body.className = "deal-body";
      var line = document.createElement("p");
      line.className = "skeleton";
      var short = document.createElement("p");
      short.className = "skeleton short";
      body.appendChild(line);
      body.appendChild(short);
      card.appendChild(media);
      card.appendChild(body);
      target.appendChild(card);
    });
  }

  function filteredRows() {
    var query = filters.q.trim().toLowerCase();
    return catalog.filter(function (deal) {
      if (filters.category && deal.category_slug !== filters.category) return false;
      if (filters.mode && offerMode(deal.offer_mode) !== filters.mode) return false;
      if (filters.merchant && deal.merchant_slug !== filters.merchant) return false;
      if (!query) return true;
      var haystack = [deal.title, deal.description, deal.merchant_name, deal.category_name].join(" ").toLowerCase();
      return haystack.indexOf(query) !== -1;
    });
  }

  function fillSelect(select, rows, placeholder) {
    if (!select) return;
    var current = select.value;
    select.replaceChildren();
    var all = document.createElement("option");
    all.value = "";
    all.textContent = placeholder;
    select.appendChild(all);
    rows.forEach(function (row) {
      var option = document.createElement("option");
      option.value = row.value;
      option.textContent = row.label;
      select.appendChild(option);
    });
    if (Array.prototype.some.call(select.options, function (option) { return option.value === current; })) {
      select.value = current;
    }
  }

  function renderFilters() {
    var chips = document.querySelector("[data-category-chips]");
    if (chips) {
      var seen = {};
      var categories = [];
      catalog.forEach(function (deal) {
        if (!deal.category_slug || seen[deal.category_slug]) return;
        seen[deal.category_slug] = true;
        categories.push({ value: deal.category_slug, label: deal.category_name || deal.category_slug });
      });
      chips.replaceChildren();
      [{ value: "", label: t("filterAll") }].concat(categories).forEach(function (category) {
        var button = document.createElement("button");
        button.type = "button";
        button.className = "chip" + (filters.category === category.value ? " is-on" : "");
        button.textContent = category.label;
        button.setAttribute("aria-pressed", filters.category === category.value ? "true" : "false");
        button.addEventListener("click", function () {
          filters.category = category.value;
          showFiltered();
        });
        chips.appendChild(button);
      });
    }
    var merchants = [];
    var seenMerchants = {};
    catalog.forEach(function (deal) {
      if (!deal.merchant_slug || seenMerchants[deal.merchant_slug]) return;
      seenMerchants[deal.merchant_slug] = true;
      merchants.push({ value: deal.merchant_slug, label: deal.merchant_name || deal.merchant_slug });
    });
    merchants.sort(function (a, b) { return a.label.localeCompare(b.label, lang); });
    fillSelect(document.querySelector("[data-merchant-filter]"), merchants, t("filterAll"));
  }

  function showFiltered() {
    renderFilters();
    var rows = filteredRows();
    var narrowed = !!(filters.q.trim() || filters.category || filters.mode || filters.merchant);
    renderList(rows, rows.length ? "" : (narrowed ? "filter" : "catalog"));
  }

  function bindFilters() {
    var form = document.querySelector("[data-deal-filters]");
    if (!form) return;
    var search = form.querySelector("[data-deal-search]");
    var mode = form.querySelector("[data-mode-filter]");
    var merchant = form.querySelector("[data-merchant-filter]");
    if (search) search.addEventListener("input", function () {
      filters.q = search.value;
      showFiltered();
    });
    if (mode) mode.addEventListener("change", function () {
      filters.mode = mode.value;
      showFiltered();
    });
    if (merchant) merchant.addEventListener("change", function () {
      filters.merchant = merchant.value;
      showFiltered();
    });
  }

  function loadList() {
    if (!client()) {
      setStatus(t("missing"), false);
      renderList([], "offline");
      return;
    }
    setStatus(t("loading"), false);
    renderLoading();
    var columns = "slug,title,description,merchant_name,category_name,current_price_cents,currency,product_image_url,cashback_estimate_label";
    var extra = ",offer_mode,original_price_cents,category_slug,merchant_slug,temperature_score,comment_count";
    client().from("public_deals").select(columns + extra).order("published_at", { ascending: false }).then(function (result) {
      if (result.error) {
        return client().from("public_deals").select(columns + ",offer_mode").order("published_at", { ascending: false });
      }
      return result;
    }).then(function (result) {
      if (!result || result.error) {
        setStatus(t("loadFailed"), true);
        renderList([], "error");
        return;
      }
      setStatus("", false);
      catalog = result.data || [];
      showFiltered();
    });
  }

  function renderDetail(deal) {
    document.querySelector("[data-deal-title]").textContent = deal.title;
    document.querySelector("[data-deal-merchant]").textContent = deal.merchant_name || "";
    document.querySelector("[data-deal-description]").textContent = deal.description;
    document.querySelector("[data-deal-price]").textContent = formatMoney(deal.current_price_cents, deal.currency);
    var was = document.querySelector("[data-deal-was]");
    var cut = shopCut(deal);
    if (was) {
      was.hidden = !cut;
      was.textContent = cut ? t("wasPrice") + " " + formatMoney(cut.original, deal.currency) + " · −" + cut.percent + " % " + t("shopCut") : "";
    }
    var badge = document.querySelector("[data-deal-mode]");
    if (badge) {
      badge.className = "offer-pill is-" + offerMode(deal.offer_mode);
      badge.textContent = offerLabel(deal.offer_mode);
      badge.hidden = false;
    }
    var estimate = document.querySelector("[data-deal-estimate]");
    estimate.textContent = offerMode(deal.offer_mode) === "listing"
      ? offerNote(deal.offer_mode)
      : offerNote(deal.offer_mode) + " " + t("estimateNote");
    var media = document.querySelector("[data-deal-media]");
    if (media) media.className = "product-art deal-media is-" + offerMode(deal.offer_mode);
    var image = document.querySelector("[data-deal-image]");
    if (image && safeImage(deal.product_image_url)) {
      image.src = deal.product_image_url;
      image.alt = deal.title;
      image.hidden = false;
    } else if (media) {
      media.classList.add("is-empty");
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
    client().from("public_deals").select("slug,title,description,merchant_name,current_price_cents,original_price_cents,currency,cashback_estimate_label,product_image_url,offer_mode").eq("slug", slug).maybeSingle().then(function (result) {
      if (result.error) {
        return client().from("public_deals").select("slug,title,description,merchant_name,current_price_cents,currency,cashback_estimate_label,product_image_url").eq("slug", slug).maybeSingle();
      }
      return result;
    }).then(function (result) {
      if (!result || result.error || !result.data) {
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
  if (page === "deals") {
    bindFilters();
    loadList();
  }
  if (page === "deal") loadDetail();
  if (page === "submit") {
    bindSubmit();
    loadOwnSubmissions();
  }
})();
