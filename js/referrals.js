// Shows a personal deal link only after the server confirms eligibility.
(function () {
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  var box = document.querySelector("[data-referral-box]");
  if (!box || !window.bundealSupabase || !window.bundealUtils) return;
  var slug = window.bundealUtils.safeSlug(params.get("slug"));
  if (!slug) return;

  window.bundealSupabase.from("public_deals").select("offer_mode").eq("slug", slug).maybeSingle().then(function (deal) {
    var mode = deal.data && deal.data.offer_mode;
    if (mode === "listing") {
      box.textContent = lang === "en"
        ? "This offer has no cashback and no personal link."
        : "Auf diesem Angebot gibt es kein Cashback und keinen persönlichen Link.";
      return;
    }
    if (mode === "cashback") {
      box.textContent = lang === "en"
        ? "Buyer cashback only. There is no personal link."
        : "Nur Käufer-Cashback. Einen persönlichen Link gibt es nicht.";
      return;
    }
    loadReferralLink();
  });

  function loadReferralLink() {
  window.bundealSupabase.rpc("referral_link_for_deal", { p_deal_slug: slug }).then(function (result) {
    var code = result.data;
    if (result.error || typeof code !== "string" || !/^[a-z0-9]{10}$/.test(code)) {
      box.textContent = lang === "en"
        ? "Your personal deal link appears after your own matched purchase on this deal."
        : "Dein persönlicher Deal-Link erscheint nach deinem eigenen zugeordneten Kauf auf diesem Deal.";
      return;
    }
    if (!window.bundealUtils.isAllowedOrigin(window.location.origin)) return;
    window.bundealSupabase.rpc("campaign_code_for_share", { p_deal_slug: slug }).then(function (campaignResult) {
      var campaign = campaignResult.data || "";
      if (campaignResult.error || !/^[a-z0-9]{10}$/.test(campaign)) campaign = "";
      var link = window.location.origin + "/deal.html?slug=" + encodeURIComponent(slug) + "&ref=" + encodeURIComponent(code);
      if (campaign) link += "&c=" + encodeURIComponent(campaign);
      box.replaceChildren();
      var label = document.createElement("p");
      label.textContent = lang === "en" ? "Your direct deal link" : "Dein direkter Deal-Link";
      var field = document.createElement("input");
      field.readOnly = true;
      field.value = link;
      var button = document.createElement("button");
      button.type = "button";
      button.className = "button button-secondary";
      button.textContent = lang === "en" ? "Copy link" : "Link kopieren";
      button.addEventListener("click", function () {
        if (navigator.clipboard) navigator.clipboard.writeText(link);
      });
      box.appendChild(label);
      box.appendChild(field);
      box.appendChild(button);
    });
  });
  }
})();
