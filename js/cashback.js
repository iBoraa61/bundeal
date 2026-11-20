// The account page reads only the signed-in user's snapshot.
(function () {
  var root = document.querySelector("[data-dashboard]");
  if (!root || !window.bundealSupabase) return;
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  var text = lang === "en"
    ? {
      empty: "Nothing here yet.",
      failed: "The overview could not be loaded.",
      open: "Open. The network has not confirmed a commission, so this is not cashback.",
      pending: "Pending. Confirmed, and not released yet.",
      available: "Available. Released, and not paid out.",
      reversed: "Reversed. The amount stays in the history.",
      rejected: "Rejected. No cashback.",
      none: "No cashback.",
      purchase: "Purchase",
      referral: "Referral",
      creator: "Creator",
      simulation: "Simulation",
      live: "Live",
      pendingLabel: "Pending",
      availableLabel: "Available",
      referrals: "Active referrals",
      buyer: "Buyer cashback",
      referralShare: "Referral bonus",
      creatorShare: "Creator share",
      apply: "Request creator review",
      channel: "Channel",
      channelHint: "For example a channel name. The role starts only after review. Do not put an email here.",
      requested: "The request is with the admin.",
      pendingNote: "Your creator request is being reviewed.",
      approvedNote: "The creator role is active. Campaigns are in the Creator section.",
      rejectedNote: "The last request was not approved. You can send a new one.",
      applyFailed: "The request was not saved.",
      pendingStatus: "Pending",
      approvedStatus: "Approved",
      rejectedStatus: "Rejected"
    }
    : {
      empty: "Noch kein Eintrag.",
      failed: "Die Übersicht konnte nicht geladen werden.",
      open: "Offen. Die Provision ist nicht bestätigt, das ist kein Cashback.",
      pending: "Ausstehend. Bestätigt und noch nicht freigegeben.",
      available: "Verfügbar. Freigegeben und noch nicht ausgezahlt.",
      reversed: "Storniert. Der Betrag bleibt in der Übersicht.",
      rejected: "Abgelehnt. Kein Cashback.",
      none: "Kein Cashback.",
      purchase: "Kauf",
      referral: "Empfehlung",
      creator: "Creator",
      simulation: "Simulation",
      live: "Live",
      pendingLabel: "Ausstehend",
      availableLabel: "Verfügbar",
      referrals: "Aktive Empfehlungen",
      buyer: "Käufer-Cashback",
      referralShare: "Empfehlungsbonus",
      creatorShare: "Creator-Beteiligung",
      apply: "Als Creator prüfen lassen",
      channel: "Kanal",
      channelHint: "Zum Beispiel ein Kanalname. Die Rolle gilt erst nach der Prüfung. Eine E-Mail gehört hier nicht hin.",
      requested: "Der Antrag liegt bei der Verwaltung.",
      pendingNote: "Dein Creator-Antrag wird geprüft.",
      approvedNote: "Die Creator-Rolle ist aktiv. Kampagnen stehen im Bereich Creator.",
      rejectedNote: "Der letzte Antrag wurde nicht bestätigt. Du kannst einen neuen senden.",
      applyFailed: "Der Antrag wurde nicht gespeichert.",
      pendingStatus: "Offen",
      approvedStatus: "Bestätigt",
      rejectedStatus: "Abgelehnt"
    };

  function euros(cents) {
    return (Number(cents) / 100).toFixed(2).replace(".", ",") + "\u00a0€";
  }

  function status(message, isError) {
    var element = document.querySelector("[data-auth-status]");
    if (!element) return;
    element.textContent = message || "";
    element.className = isError ? "form-error" : "status";
  }

  function showTab(name) {
    var tabs = root.querySelectorAll("[data-dash-tab]");
    var found = false;
    tabs.forEach(function (tab) {
      if (tab.hidden) return;
      var selected = tab.getAttribute("data-dash-tab") === name;
      if (selected) found = true;
      tab.setAttribute("aria-selected", selected ? "true" : "false");
    });
    if (!found) {
      name = "overview";
      tabs.forEach(function (tab) {
        tab.setAttribute("aria-selected", tab.getAttribute("data-dash-tab") === "overview" ? "true" : "false");
      });
    }
    root.querySelectorAll("[data-dash-panel]").forEach(function (panel) {
      panel.classList.toggle("is-active", panel.getAttribute("data-dash-panel") === name);
    });
    tabs.forEach(function (tab) {
      if (tab.getAttribute("aria-selected") !== "true") return;
      var nav = tab.parentElement;
      if (!nav) return;
      nav.scrollLeft = Math.max(0, tab.offsetLeft - (nav.clientWidth - tab.offsetWidth) / 2);
    });
    if (found && window.location.hash !== "#" + name) history.replaceState(null, "", "#" + name);
  }

  function shareAmount(shares, environment, bucket, field) {
    var row = (shares || []).find(function (entry) {
      return entry.environment === environment && entry.bucket === bucket;
    });
    return row ? Number(row[field] || 0) : 0;
  }

  function balanceAmount(balances, environment, field) {
    var row = (balances || []).find(function (entry) { return entry.environment === environment; });
    return row ? Number(row[field] || 0) : 0;
  }

  function renderBalances(data, isCreator) {
    var target = document.querySelector("[data-cashback-balances]");
    if (!target) return;
    target.replaceChildren();
    ["simulation", "live"].forEach(function (environment) {
      var card = document.createElement("article");
      card.className = "card";
      var title = document.createElement("h3");
      title.textContent = text[environment];
      var pending = document.createElement("p");
      pending.textContent = text.pendingLabel + " " + euros(balanceAmount(data.balances, environment, "pending_cents"));
      var available = document.createElement("p");
      available.textContent = text.availableLabel + " " + euros(balanceAmount(data.balances, environment, "available_cents"));
      var split = document.createElement("p");
      split.className = "fine";
      split.textContent = text.buyer + " " + euros(shareAmount(data.shares, environment, "basic_cashback", "pending_cents") + shareAmount(data.shares, environment, "basic_cashback", "available_cents"))
        + " · " + text.referralShare + " " + euros(shareAmount(data.shares, environment, "referral_bonus", "pending_cents") + shareAmount(data.shares, environment, "referral_bonus", "available_cents"))
        + (isCreator ? " · " + text.creatorShare + " " + euros(shareAmount(data.shares, environment, "creator_share", "pending_cents") + shareAmount(data.shares, environment, "creator_share", "available_cents")) : "");
      card.appendChild(title);
      card.appendChild(pending);
      card.appendChild(available);
      card.appendChild(split);
      target.appendChild(card);
    });
  }

  function renderHistory(rows, kinds) {
    var list = document.querySelector(kinds.indexOf("purchase") !== -1 && kinds.length === 1
      ? "[data-purchase-history]"
      : "[data-referral-history]");
    if (kinds.indexOf("creator") !== -1 && kinds.length === 1) list = document.querySelector("[data-creator-history]");
    if (!list) return;
    list.replaceChildren();
    var visible = (rows || []).filter(function (row) { return kinds.indexOf(row.kind) !== -1; });
    if (!visible.length) {
      var empty = document.createElement("p");
      empty.textContent = text.empty;
      list.appendChild(empty);
      return;
    }
    visible.forEach(function (row) {
      var article = document.createElement("article");
      article.className = "card";
      var title = document.createElement("h3");
      title.textContent = (row.deal_title || text[row.kind] || "") + " · " + text[row.environment];
      var body = document.createElement("p");
      var label = text[row.cashback_status] || text.none;
      body.textContent = (row.amount_cents == null ? "" : euros(row.amount_cents) + " · ") + label;
      article.appendChild(title);
      article.appendChild(body);
      list.appendChild(article);
    });
  }

  function renderReferrals(data) {
    var target = document.querySelector("[data-referral-count]");
    if (target) target.textContent = text.referrals + ": " + Number(data.referral_count || 0);
  }

  function renderSubmissions(rows) {
    var list = document.querySelector("[data-dashboard-submissions]");
    if (!list) return;
    list.replaceChildren();
    if (!rows || !rows.length) {
      var empty = document.createElement("p");
      empty.textContent = text.empty;
      list.appendChild(empty);
      return;
    }
    rows.forEach(function (row) {
      var article = document.createElement("article");
      article.className = "card";
      var title = document.createElement("h3");
      title.textContent = row.title;
      var body = document.createElement("p");
      body.textContent = text[row.status + "Status"] || row.status;
      article.appendChild(title);
      article.appendChild(body);
      list.appendChild(article);
    });
  }

  function renderApplication(application, isCreator) {
    var box = document.querySelector("[data-creator-apply]");
    var creatorTab = document.querySelector("[data-dash-tab='creator']");
    if (creatorTab) creatorTab.hidden = !isCreator;
    if (!box) return;
    box.replaceChildren();
    if (isCreator) {
      var done = document.createElement("p");
      done.textContent = text.approvedNote;
      box.appendChild(done);
      return;
    }
    var note = document.createElement("p");
    note.className = "fine";
    if (application && application.status === "pending") {
      note.textContent = text.pendingNote;
      box.appendChild(note);
      return;
    }
    note.textContent = application && application.status === "rejected" ? text.rejectedNote : text.channelHint;
    var form = document.createElement("form");
    form.className = "suggestion-form";
    var label = document.createElement("label");
    label.textContent = text.channel + " ";
    var input = document.createElement("textarea");
    input.name = "channel";
    input.required = true;
    input.minLength = 8;
    input.maxLength = 160;
    label.appendChild(input);
    var button = document.createElement("button");
    button.className = "button button-primary";
    button.type = "submit";
    button.textContent = text.apply;
    form.appendChild(label);
    form.appendChild(button);
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var channel = input.value.trim();
      if (channel.length < 8 || channel.length > 160) {
        status(text.applyFailed, true);
        return;
      }
      button.disabled = true;
      window.bundealSupabase.rpc("request_creator_role", { p_channel: channel }).then(function (result) {
        button.disabled = false;
        if (result.error) {
          status(text.applyFailed, true);
          return;
        }
        status(text.requested, false);
        renderApplication({ status: "pending" }, false);
      });
    });
    box.appendChild(note);
    box.appendChild(form);
  }

  root.querySelectorAll("[data-dash-tab]").forEach(function (tab) {
    tab.addEventListener("click", function () {
      if (tab.hidden) return;
      showTab(tab.getAttribute("data-dash-tab"));
    });
  });

  window.bundealSupabase.auth.getSession().then(function (result) {
    if (!result.data.session) return;
    var userId = result.data.session.user.id;
    return Promise.all([
      window.bundealSupabase.rpc("cashback_account_snapshot"),
      window.bundealSupabase.rpc("creator_application_snapshot"),
      window.bundealSupabase.from("user_roles").select("role").eq("user_id", userId)
    ]);
  }).then(function (results) {
    if (!results) return;
    var snapshot = results[0];
    var application = results[1];
    var roles = results[2];
    if (snapshot.error || !snapshot.data) {
      status(text.failed, true);
      return;
    }
    var isCreator = !!(roles.data && roles.data.some(function (row) { return row.role === "creator"; }));
    renderBalances(snapshot.data, isCreator);
    renderHistory(snapshot.data.history, ["purchase"]);
    renderHistory(snapshot.data.history, ["referral"]);
    renderHistory(snapshot.data.history, ["creator"]);
    renderReferrals(snapshot.data);
    renderSubmissions(snapshot.data.submissions);
    renderApplication(application.data, isCreator);
    var requested = (window.location.hash || "#overview").slice(1);
    showTab(requested === "creator" && !isCreator ? "overview" : requested);
  }).catch(function () {
    status(text.failed, true);
  });
})();
