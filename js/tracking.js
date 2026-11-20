// Starts a server-side click. The browser never chooses the affiliate URL.
(function () {
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  var button = document.querySelector("[data-merchant-click]");
  if (!button) return;

  button.addEventListener("click", function () {
    var utils = window.bundealUtils || {};
    var slug = utils.safeSlug ? utils.safeSlug(params.get("slug")) : "";
    var referrer = params.get("ref") || "";
    var campaign = params.get("c") || "";
    var status = document.querySelector("[data-deal-status]");
    if (!slug || !window.bundealSupabase) {
      if (status) status.textContent = lang === "en" ? "This deal is not available." : "Dieser Deal ist nicht verfügbar.";
      return;
    }
    if (!/^[a-z0-9]{10}$/.test(referrer)) referrer = "";
    if (!/^[a-z0-9]{10}$/.test(campaign)) campaign = "";

    button.disabled = true;
    window.bundealSupabase.auth.getSession().then(function (result) {
      if (!result.data.session) {
        var next = "login.html?next=deal.html&slug=" + encodeURIComponent(slug);
        if (referrer) next += "&ref=" + encodeURIComponent(referrer);
        if (campaign) next += "&c=" + encodeURIComponent(campaign);
        if (lang === "en") next += "&lang=en";
        window.location.assign(next);
        return null;
      }
      return window.bundealSupabase.rpc("begin_affiliate_click", {
        p_deal_slug: slug,
        p_referrer_code: referrer || null,
        p_campaign_code: campaign || null
      });
    }).then(function (result) {
      if (!result) return;
      var url = result.data && result.data.outbound_url;
      if (result.error || typeof url !== "string" || url.indexOf("https://") !== 0) {
        button.disabled = false;
        if (status) status.textContent = lang === "en" ? "The merchant link could not be opened." : "Der Händler-Link konnte nicht geöffnet werden.";
        return;
      }
      window.location.assign(url);
    }).catch(function () {
      button.disabled = false;
      if (status) status.textContent = lang === "en" ? "The merchant link could not be opened." : "Der Händler-Link konnte nicht geöffnet werden.";
    });
  });
})();
