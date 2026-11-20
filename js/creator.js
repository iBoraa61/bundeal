// Creator campaigns on the account page. Amounts come from the server snapshot.
(function () {
  var root = document.querySelector("[data-creator-campaigns]");
  if (!root || !window.bundealSupabase || !window.bundealUtils) return;
  var currentUser = "";
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  var text = lang === "en"
    ? {
      title: "Creator campaigns",
      note: "A campaign runs for 90 days. The 10% comes out of BunDeal's share and only after the network confirms the commission. There is no payout here.",
      locked: "Campaigns can be started only by an account with the creator role.",
      deal: "Deal",
      start: "Start campaign",
      empty: "You have no campaign yet.",
      failed: "The campaign was not saved.",
      started: "Campaign started.",
      ended: "Campaign ended.",
      end: "End campaign",
      copy: "Copy link",
      pending: "Open purchases",
      confirmed: "Confirmed creator share",
      simulation: "Simulation",
      live: "Live"
    }
    : {
      title: "Creator-Kampagnen",
      note: "Eine Kampagne läuft 90 Tage. Die 10 % kommen aus dem BunDeal-Anteil und erst nach bestätigter Provision. Eine Auszahlung gibt es hier nicht.",
      locked: "Kampagnen kann nur ein Konto mit der Rolle Creator starten.",
      deal: "Deal",
      start: "Kampagne starten",
      empty: "Du hast noch keine Kampagne.",
      failed: "Die Kampagne wurde nicht gespeichert.",
      started: "Kampagne gestartet.",
      ended: "Kampagne beendet.",
      end: "Kampagne beenden",
      copy: "Link kopieren",
      pending: "Offene Käufe",
      confirmed: "Bestätigte Creator-Beteiligung",
      simulation: "Simulation",
      live: "Live"
    };

  function euros(cents) {
    return (Number(cents) / 100).toFixed(2).replace(".", ",") + "\u00a0€";
  }

  function status(message, isError) {
    var element = document.querySelector("[data-auth-status]");
    if (!element) return;
    element.textContent = message || "";
    element.classList.toggle("error", !!isError);
  }

  function render(campaigns, code, canCreate) {
    var list = root.querySelector("[data-creator-list]");
    list.replaceChildren();
    if (!campaigns.length) {
      if (!canCreate) return;
      var empty = document.createElement("p");
      empty.textContent = text.empty;
      list.appendChild(empty);
      return;
    }
    campaigns.forEach(function (row) {
      var article = document.createElement("article");
      article.className = "card";
      var title = document.createElement("h3");
      title.textContent = row.deal_title + " · " + row.public_code;
      var body = document.createElement("p");
      body.textContent = text.simulation + " " + euros(row.simulation_creator_cents)
        + " · " + text.pending + " " + row.simulation_pending
        + " · " + text.live + " " + euros(row.live_creator_cents)
        + " · " + text.pending + " " + row.live_pending;
      article.appendChild(title);
      article.appendChild(body);
      if (row.status === "active" && code && window.bundealUtils.isAllowedOrigin(window.location.origin)) {
        var link = window.location.origin + "/deal.html?slug=" + encodeURIComponent(row.deal_slug)
          + "&ref=" + encodeURIComponent(code) + "&c=" + encodeURIComponent(row.public_code);
        var field = document.createElement("input");
        field.readOnly = true;
        field.value = link;
        var copy = document.createElement("button");
        copy.type = "button";
        copy.className = "button button-secondary";
        copy.textContent = text.copy;
        copy.addEventListener("click", function () {
          if (navigator.clipboard) navigator.clipboard.writeText(link);
        });
        var end = document.createElement("button");
        end.type = "button";
        end.className = "button button-secondary";
        end.textContent = text.end;
        end.addEventListener("click", function () {
          window.bundealSupabase.rpc("end_creator_campaign", { p_public_code: row.public_code }).then(function (result) {
            status(result.error ? text.failed : text.ended, !!result.error);
            if (!result.error) load(currentUser, true);
          });
        });
        var actions = document.createElement("div");
        actions.className = "button-row";
        actions.appendChild(copy);
        actions.appendChild(end);
        article.appendChild(field);
        article.appendChild(actions);
      }
      list.appendChild(article);
    });
  }

  function load(userId, canCreate) {
    Promise.all([
      window.bundealSupabase.rpc("creator_campaign_snapshot"),
      window.bundealSupabase.from("profiles").select("referral_code").eq("id", userId).maybeSingle()
    ]).then(function (results) {
      var campaigns = results[0];
      var profile = results[1];
      if (campaigns.error || !Array.isArray(campaigns.data)) {
        status(text.failed, true);
        return;
      }
      var code = profile.data && profile.data.referral_code;
      render(campaigns.data, /^[a-z0-9]{10}$/.test(code || "") ? code : "", canCreate);
    });
  }

  function fillDeals() {
    var select = root.querySelector("select");
    window.bundealSupabase.from("deals").select("slug,title").eq("status", "published").order("title").then(function (result) {
      if (!select || result.error) return;
      (result.data || []).forEach(function (deal) {
        var option = document.createElement("option");
        option.value = deal.slug;
        option.textContent = deal.title;
        select.appendChild(option);
      });
    });
  }

  function mount() {
    var heading = document.createElement("h2");
    heading.textContent = text.title;
    var note = document.createElement("p");
    note.className = "fine";
    note.textContent = text.note;
    var form = document.createElement("form");
    form.className = "suggestion-form";
    var label = document.createElement("label");
    label.textContent = text.deal + " ";
    var select = document.createElement("select");
    select.name = "deal";
    select.required = true;
    label.appendChild(select);
    var button = document.createElement("button");
    button.className = "button button-primary";
    button.type = "submit";
    button.textContent = text.start;
    form.appendChild(label);
    form.appendChild(button);
    var list = document.createElement("div");
    list.className = "grid-2";
    list.setAttribute("data-creator-list", "");
    root.appendChild(heading);
    root.appendChild(note);
    root.appendChild(form);
    root.appendChild(list);
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      window.bundealSupabase.rpc("create_creator_campaign", {
        p_deal_slug: select.value
      }).then(function (result) {
        status(result.error ? text.failed : text.started, !!result.error);
        if (!result.error) load(currentUser, true);
      });
    });
    fillDeals();
    load(currentUser, true);
  }

  window.bundealSupabase.auth.getSession().then(function (result) {
    if (!result.data.session) return;
    currentUser = result.data.session.user.id;
    window.bundealSupabase.from("user_roles").select("role").eq("user_id", currentUser).then(function (roles) {
      var canCreate = !!(roles.data && roles.data.some(function (row) { return row.role === "creator"; }));
      if (canCreate) mount();
    });
  });
})();
