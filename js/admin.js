// Admin moderation. Authorization is enforced by the database, not by hiding this page.
(function () {
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  if (document.body.getAttribute("data-page") !== "admin") return;

  function status(message, isError) {
    var element = document.querySelector("[data-admin-status]");
    if (!element) return;
    element.textContent = message || "";
    element.className = isError ? "form-error" : "status";
  }

  function client() {
    return window.bundealSupabase;
  }

  function requireAdmin() {
    if (!client()) {
      status(lang === "en" ? "Administration is not connected in this public preview." : "Die Verwaltung ist in dieser öffentlichen Vorschau nicht angebunden.", true);
      return Promise.resolve(false);
    }
    return client().auth.getSession().then(function (result) {
      var session = result.data.session;
      if (!session) {
        window.location.assign("login.html?next=admin.html" + (lang === "en" ? "&lang=en" : ""));
        return false;
      }
      return client().from("user_roles").select("role").eq("user_id", session.user.id);
    }).then(function (result) {
      if (result === false) return false;
      var isAdmin = result && result.data && result.data.some(function (row) { return row.role === "admin"; });
      if (!isAdmin) {
        status(lang === "en" ? "This account is not an admin." : "Dieses Konto ist kein Admin.", true);
        return false;
      }
      return true;
    });
  }

  function loadMerchants() {
    var select = document.querySelector("[data-merchant-select]");
    var dealSelect = document.querySelector("[data-deal-select]");
    if (!select || !dealSelect) return;
    client().from("merchants").select("id,name,slug").order("name").then(function (result) {
      select.replaceChildren();
      (result.data || []).forEach(function (merchant) {
        var option = document.createElement("option");
        option.value = merchant.id;
        option.textContent = merchant.name;
        select.appendChild(option);
      });
    });
    client().from("deals").select("id,title,slug").eq("status", "published").order("title").then(function (result) {
      dealSelect.replaceChildren();
      (result.data || []).forEach(function (deal) {
        var option = document.createElement("option");
        option.value = deal.id;
        option.textContent = deal.title;
        dealSelect.appendChild(option);
      });
    });
  }

  function loadSubmissions() {
    var list = document.querySelector("[data-submission-list]");
    if (!list) return;
    client().from("deal_submissions").select("id,proposed_title,proposed_url,proposed_price_cents,currency,submission_status").eq("submission_status", "pending").then(function (result) {
      list.replaceChildren();
      (result.data || []).forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.proposed_title;
        var url = document.createElement("p");
        url.textContent = row.proposed_url;
        var approve = document.createElement("button");
        approve.type = "button";
        approve.className = "button button-primary";
        approve.textContent = lang === "en" ? "Approve" : "Freigeben";
        approve.addEventListener("click", function () {
          var slug = window.prompt(lang === "en" ? "Deal slug" : "Deal-Slug");
          var merchant = document.querySelector("[data-merchant-select]").value;
          if (!slug || !merchant) return;
          client().rpc("review_deal_submission", {
            p_submission_id: row.id,
            p_decision: "approved",
            p_comment: null,
            p_merchant_id: merchant,
            p_slug: slug,
            p_price_cents: row.proposed_price_cents,
            p_currency: row.currency || "EUR"
          }).then(function (response) {
            status(response.error ? (lang === "en" ? "Review failed." : "Die Prüfung ist fehlgeschlagen.") : (lang === "en" ? "Suggestion published." : "Vorschlag veröffentlicht."), !!response.error);
            if (!response.error) {
              loadSubmissions();
              loadMerchants();
            }
          });
        });
        var reject = document.createElement("button");
        reject.type = "button";
        reject.className = "button button-secondary";
        reject.textContent = lang === "en" ? "Reject" : "Ablehnen";
        reject.addEventListener("click", function () {
          client().rpc("review_deal_submission", {
            p_submission_id: row.id,
            p_decision: "rejected",
            p_comment: null
          }).then(function () {
            loadSubmissions();
          });
        });
        article.appendChild(title);
        article.appendChild(url);
        article.appendChild(approve);
        article.appendChild(reject);
        list.appendChild(article);
      });
    });
  }

  function euros(cents) {
    return (Number(cents) / 100).toFixed(2).replace(".", ",") + "\u00a0€";
  }

  function loadCashback() {
    var current = document.querySelector("[data-cashback-current]");
    var recent = document.querySelector("[data-cashback-recent]");
    if (!current || !recent) return;
    client().rpc("cashback_admin_snapshot").then(function (result) {
      current.replaceChildren();
      recent.replaceChildren();
      if (result.error || !result.data) {
        status(lang === "en" ? "Cashback overview failed." : "Die Cashback-Übersicht ist fehlgeschlagen.", true);
        return;
      }
      var snapshot = result.data;
      var lines = [
        ["Regel", snapshot.rule.version + " · " + snapshot.rule.basic + " / " + snapshot.rule.referral + " / " + (snapshot.rule.creator || 0) + " / " + snapshot.rule.platform],
        ["Freigabe", snapshot.policy.version + " · " + snapshot.policy.release_delay_days + (lang === "en" ? " days" : " Tage")],
        ["Gemeinschaftsanteil", snapshot.policy.community_treatment],
        ["Währung", snapshot.policy.currency],
        ["Abweichungen", String(snapshot.reconciliation_failures)],
        ["Vorgemerkt, Simulation", String(snapshot.pending_entries)]
      ];
      lines.forEach(function (pair) {
        var term = document.createElement("dt");
        term.textContent = pair[0];
        var value = document.createElement("dd");
        value.textContent = pair[1];
        current.appendChild(term);
        current.appendChild(value);
      });
      (snapshot.recent || []).forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.external_transaction_id + " · " + row.environment;
        var body = document.createElement("p");
        body.textContent = euros(row.gross_commission_cents)
          + " → " + euros(row.basic_cashback_cents)
          + " / " + euros(row.referral_bonus_cents)
          + " / " + euros(row.unassigned_community_cents)
          + " / " + euros(row.creator_share_cents || 0)
          + " / " + euros(row.bundeal_revenue_cents)
          + (row.rounding_adjustment_cents ? " · Rundung " + euros(row.rounding_adjustment_cents) : "");
        article.appendChild(title);
        article.appendChild(body);
        recent.appendChild(article);
      });
    });
  }

  function loadCreatorApplications() {
    var list = document.querySelector("[data-creator-applications]");
    if (!list) return;
    client().rpc("creator_application_admin_snapshot").then(function (result) {
      list.replaceChildren();
      if (result.error || !Array.isArray(result.data)) return;
      var pending = result.data.filter(function (row) { return row.status === "pending"; });
      if (!pending.length) {
        var empty = document.createElement("p");
        empty.textContent = lang === "en" ? "No open creator request." : "Kein offener Creator-Antrag.";
        list.appendChild(empty);
        return;
      }
      pending.forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = (row.display_name || row.username) + " · " + row.username;
        var body = document.createElement("p");
        body.textContent = row.channel_note;
        var actions = document.createElement("div");
        actions.className = "button-row";
        var approve = document.createElement("button");
        approve.type = "button";
        approve.className = "button button-primary";
        approve.textContent = lang === "en" ? "Confirm role" : "Rolle bestätigen";
        var reject = document.createElement("button");
        reject.type = "button";
        reject.className = "button button-secondary";
        reject.textContent = lang === "en" ? "Reject" : "Ablehnen";
        function review(enabled) {
          client().rpc("review_creator_application", {
            p_application_id: row.id,
            p_approve: enabled
          }).then(function (reviewResult) {
            status(reviewResult.error
              ? (lang === "en" ? "The request was not reviewed." : "Der Antrag wurde nicht geprüft.")
              : (enabled
                ? (lang === "en" ? "Creator role confirmed." : "Creator-Rolle bestätigt.")
                : (lang === "en" ? "Request rejected." : "Antrag abgelehnt.")), !!reviewResult.error);
            if (!reviewResult.error) loadCreatorApplications();
          });
        }
        approve.addEventListener("click", function () { review(true); });
        reject.addEventListener("click", function () { review(false); });
        actions.appendChild(approve);
        actions.appendChild(reject);
        article.appendChild(title);
        article.appendChild(body);
        article.appendChild(actions);
        list.appendChild(article);
      });
    });
  }

  function loadCreatorAdmin() {
    var list = document.querySelector("[data-creator-admin]");
    if (!list) return;
    client().rpc("creator_admin_snapshot").then(function (result) {
      list.replaceChildren();
      if (result.error || !Array.isArray(result.data)) return;
      result.data.forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.creator_name + " · " + row.deal_title;
        var body = document.createElement("p");
        body.textContent = row.public_code + " · " + row.status
          + " · Simulation " + euros(row.simulation_creator_cents)
          + " · Live " + euros(row.live_creator_cents);
        article.appendChild(title);
        article.appendChild(body);
        if (row.status === "active") {
          var end = document.createElement("button");
          end.type = "button";
          end.className = "button button-secondary";
          end.textContent = lang === "en" ? "End campaign" : "Kampagne beenden";
          end.addEventListener("click", function () {
            client().rpc("end_creator_campaign", { p_public_code: row.public_code }).then(function () {
              loadCreatorAdmin();
            });
          });
          article.appendChild(end);
        }
        list.appendChild(article);
      });
    });
  }

  function stamp(value) {
    if (!value) return "";
    var date = new Date(value);
    if (isNaN(date.getTime())) return "";
    return date.toLocaleDateString(lang === "en" ? "en-GB" : "de-DE", { day: "2-digit", month: "short", year: "numeric" });
  }

  function fillCards(selector, rows, render) {
    var list = document.querySelector(selector);
    if (!list) return;
    list.replaceChildren();
    if (!rows.length) {
      var empty = document.createElement("p");
      empty.textContent = lang === "en" ? "Nothing here yet." : "Noch kein Eintrag.";
      list.appendChild(empty);
      return;
    }
    rows.forEach(function (row) {
      list.appendChild(render(row));
    });
  }

  function loadOperations() {
    if (!document.querySelector("[data-admin-rounds]")) return;
    client().rpc("admin_operations_snapshot").then(function (result) {
      if (result.error || !result.data) {
        status(lang === "en" ? "The operations view could not be loaded." : "Die Betriebsansicht konnte nicht geladen werden.", true);
        return;
      }
      var data = result.data;
      fillCards("[data-admin-rounds]", data.rounds || [], function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.deal_title + " · " + row.environment;
        var body = document.createElement("p");
        body.textContent = stamp(row.period_start) + " – " + stamp(row.period_end);
        var button = document.createElement("button");
        button.type = "button";
        button.className = "button button-secondary";
        button.textContent = lang === "en" ? "Close round" : "Runde schließen";
        button.addEventListener("click", function () {
          var confirmed = window.confirm(lang === "en"
            ? "Close this month? New purchases in this month can no longer be assigned."
            : "Diese Monatsrunde schließen? Neue Käufe in diesem Monat können danach nicht mehr zugeordnet werden.");
          if (!confirmed) return;
          client().rpc("close_deal_round", { p_round_id: row.id }).then(function (response) {
            status(response.error ? (lang === "en" ? "The round was not closed." : "Die Runde wurde nicht geschlossen.") : (lang === "en" ? "Round closed." : "Runde geschlossen."), !!response.error);
            if (!response.error) loadOperations();
          });
        });
        article.appendChild(title);
        article.appendChild(body);
        article.appendChild(button);
        return article;
      });
      fillCards("[data-admin-transactions]", data.transactions || [], function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.deal_title + " · " + row.environment;
        var body = document.createElement("p");
        body.textContent = row.transaction_status + " · " + euros(row.commission_cents)
          + (row.buyer_name ? " · " + row.buyer_name : "")
          + " · " + stamp(row.transaction_date);
        article.appendChild(title);
        article.appendChild(body);
        return article;
      });
      fillCards("[data-admin-events]", data.events || [], function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.event_type + " · " + row.environment;
        var body = document.createElement("p");
        body.textContent = row.processing_status + (row.error_code ? " · " + row.error_code : "") + " · " + stamp(row.received_at);
        article.appendChild(title);
        article.appendChild(body);
        return article;
      });
      fillCards("[data-admin-risks]", data.risks || [], function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.risk_type + " · " + row.severity;
        var body = document.createElement("p");
        body.textContent = row.status + " · " + stamp(row.created_at);
        article.appendChild(title);
        article.appendChild(body);
        if (row.status === "open") {
          var button = document.createElement("button");
          button.type = "button";
          button.className = "button button-secondary";
          button.textContent = lang === "en" ? "Close" : "Schließen";
          button.addEventListener("click", function () {
            client().rpc("close_risk_event", { p_event_id: row.id }).then(function (response) {
              status(response.error ? (lang === "en" ? "The risk was not closed." : "Das Risiko wurde nicht geschlossen.") : (lang === "en" ? "Risk closed." : "Risiko geschlossen."), !!response.error);
              if (!response.error) loadOperations();
            });
          });
          article.appendChild(button);
        }
        return article;
      });
      var payouts = document.querySelector("[data-admin-payouts]");
      if (payouts) {
        payouts.replaceChildren();
        var ready = data.payout_ready || [];
        var accounts = data.payout_accounts || [];
        if (!ready.length && !accounts.length) {
          var empty = document.createElement("p");
          empty.textContent = lang === "en" ? "Nothing is ready. No payout is sent from here." : "Nichts ist vorbereitet. Von hier wird nichts ausgezahlt.";
          payouts.appendChild(empty);
        } else {
          ready.forEach(function (row) {
            var article = document.createElement("article");
            article.className = "card";
            var title = document.createElement("h3");
            title.textContent = row.environment;
            var body = document.createElement("p");
            body.textContent = euros(row.cents);
            article.appendChild(title);
            article.appendChild(body);
            payouts.appendChild(article);
          });
          accounts.forEach(function (row) {
            var article = document.createElement("article");
            article.className = "card";
            var title = document.createElement("h3");
            title.textContent = row.name;
            var body = document.createElement("p");
            body.textContent = row.environment + " · " + euros(row.cents);
            article.appendChild(title);
            article.appendChild(body);
            payouts.appendChild(article);
          });
        }
      }
      fillCards("[data-admin-audit]", data.audit || [], function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.action;
        var body = document.createElement("p");
        body.textContent = (row.actor_name || "") + " · " + (row.target_table || "") + (row.environment ? " · " + row.environment : "") + " · " + stamp(row.created_at);
        article.appendChild(title);
        article.appendChild(body);
        return article;
      });
    });
  }

  function showAdminTab(name) {
    var tabs = document.querySelectorAll("[data-admin-tab]");
    var panels = document.querySelectorAll("[data-admin-panel]");
    var found = false;
    tabs.forEach(function (tab) {
      var selected = tab.getAttribute("data-admin-tab") === name;
      if (selected) found = true;
      tab.setAttribute("aria-selected", selected ? "true" : "false");
    });
    if (!found) {
      name = "merchants";
      tabs.forEach(function (tab) {
        tab.setAttribute("aria-selected", tab.getAttribute("data-admin-tab") === name ? "true" : "false");
      });
    }
    panels.forEach(function (panel) {
      panel.classList.toggle("is-active", panel.getAttribute("data-admin-panel") === name);
    });
    tabs.forEach(function (tab) {
      if (tab.getAttribute("aria-selected") !== "true") return;
      var nav = tab.parentElement;
      if (!nav) return;
      nav.scrollLeft = Math.max(0, tab.offsetLeft - (nav.clientWidth - tab.offsetWidth) / 2);
    });
    if (found && window.location.hash !== "#" + name) {
      history.replaceState(null, "", "#" + name);
    }
  }

  function showOpsTab(name) {
    var tabs = document.querySelectorAll("[data-ops-tab]");
    var found = false;
    tabs.forEach(function (tab) {
      var selected = tab.getAttribute("data-ops-tab") === name;
      if (selected) found = true;
      tab.setAttribute("aria-selected", selected ? "true" : "false");
    });
    if (!found) {
      name = "rounds";
      tabs.forEach(function (tab) {
        tab.setAttribute("aria-selected", tab.getAttribute("data-ops-tab") === name ? "true" : "false");
      });
    }
    document.querySelectorAll("[data-ops-panel]").forEach(function (panel) {
      panel.classList.toggle("is-active", panel.getAttribute("data-ops-panel") === name);
    });
    tabs.forEach(function (tab) {
      if (tab.getAttribute("aria-selected") !== "true") return;
      var nav = tab.parentElement;
      if (!nav) return;
      nav.scrollLeft = Math.max(0, tab.offsetLeft - (nav.clientWidth - tab.offsetWidth) / 2);
    });
  }

  document.querySelectorAll("[data-ops-tab]").forEach(function (tab) {
    tab.addEventListener("click", function () {
      showOpsTab(tab.getAttribute("data-ops-tab"));
    });
  });
  showOpsTab("rounds");

  document.querySelectorAll("[data-admin-tab]").forEach(function (tab) {
    tab.addEventListener("click", function () {
      showAdminTab(tab.getAttribute("data-admin-tab"));
    });
  });
  showAdminTab((window.location.hash || "#merchants").slice(1));

  requireAdmin().then(function (allowed) {
    if (!allowed) return;
    loadMerchants();
    loadSubmissions();
    loadCashback();
    loadCreatorAdmin();
    loadCreatorApplications();
    loadOperations();
    document.querySelector("[data-merchant-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      client().rpc("create_merchant", {
        p_name: form.name.value.trim(),
        p_slug: form.slug.value.trim(),
        p_website_url: form.website.value.trim()
      }).then(function (result) {
        status(result.error ? (lang === "en" ? "Merchant was not saved." : "Der Händler wurde nicht gespeichert.") : (lang === "en" ? "Merchant saved." : "Händler gespeichert."), !!result.error);
        if (!result.error) {
          form.reset();
          loadMerchants();
        }
      });
    });
    document.querySelector("[data-deal-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      client().rpc("create_published_deal", {
        p_merchant_id: form.merchant_id.value,
        p_category_slug: "allgemein",
        p_slug: form.slug.value.trim(),
        p_title: form.title.value.trim(),
        p_description: form.description.value.trim(),
        p_price_cents: Number(form.price.value),
        p_currency: "EUR",
        p_image_url: form.image.value.trim() || null
      }).then(function (result) {
        status(result.error ? (lang === "en" ? "Deal was not published." : "Der Deal wurde nicht veröffentlicht.") : (lang === "en" ? "Deal published." : "Deal veröffentlicht."), !!result.error);
        if (!result.error) {
          form.reset();
          loadMerchants();
        }
      });
    });
    document.querySelector("[data-link-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      client().rpc("attach_affiliate_link", {
        p_deal_id: form.deal_id.value,
        p_network: form.network.value.trim(),
        p_account_reference: form.account.value.trim(),
        p_environment: form.environment.value,
        p_affiliate_url: form.url.value.trim(),
        p_parameter: form.parameter.value.trim()
      }).then(function (result) {
        status(result.error ? (lang === "en" ? "Link was not saved." : "Der Link wurde nicht gespeichert.") : (lang === "en" ? "Tracking link saved." : "Tracking-Link gespeichert."), !!result.error);
      });
    });
    document.querySelector("[data-import-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      var events;
      try {
        events = JSON.parse(form.events.value);
      } catch (error) {
        status(lang === "en" ? "The JSON is invalid." : "Das JSON ist ungültig.", true);
        return;
      }
      client().rpc("import_affiliate_events", {
        p_events: events,
        p_environment: "simulation"
      }).then(function (result) {
        status(result.error ? (lang === "en" ? "Import failed." : "Der Import ist fehlgeschlagen.") : JSON.stringify(result.data), !!result.error);
        if (!result.error) loadCashback();
      });
    });
    document.querySelector("[data-rule-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      var basic = Number(form.basic.value);
      var referral = Number(form.referral.value);
      var creatorPoints = Number(form.creator.value || 0);
      var platform = Number(form.platform.value);
      if (basic + referral + creatorPoints + platform !== 10000) {
        status(lang === "en" ? "The shares must add up to 10000." : "Die Anteile müssen zusammen 10000 ergeben.", true);
        return;
      }
      client().rpc("publish_commission_rule", {
        p_version: form.version.value.trim(),
        p_basic_points: basic,
        p_referral_points: referral,
        p_platform_points: platform,
        p_creator_points: creatorPoints
      }).then(function (result) {
        status(result.error ? (lang === "en" ? "The rule was not published." : "Die Regel wurde nicht veröffentlicht.") : (lang === "en" ? "Rule published." : "Regel veröffentlicht."), !!result.error);
        if (!result.error) loadCashback();
      });
    });
    document.querySelector("[data-policy-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      client().rpc("publish_cashback_policy", {
        p_version: form.version.value.trim(),
        p_release_delay_days: Number(form.delay.value)
      }).then(function (result) {
        status(result.error ? (lang === "en" ? "The policy was not saved." : "Das Regelwerk wurde nicht gespeichert.") : (lang === "en" ? "Policy saved." : "Regelwerk gespeichert."), !!result.error);
        if (!result.error) loadCashback();
      });
    });
    document.querySelector("[data-creator-role-form]").addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      var enabled = event.submitter && event.submitter.value === "true";
      client().rpc("set_creator_role", {
        p_username: form.username.value.trim(),
        p_enabled: enabled
      }).then(function (result) {
        status(result.error
          ? (lang === "en" ? "The creator role was not changed." : "Die Creator-Rolle wurde nicht geändert.")
          : (enabled
            ? (lang === "en" ? "Creator role granted." : "Creator-Rolle vergeben.")
            : (lang === "en" ? "Creator role removed." : "Creator-Rolle entzogen.")), !!result.error);
      });
    });
    document.querySelector("[data-release-due]").addEventListener("click", function () {
      client().rpc("release_due_cashback", { p_environment: "simulation" }).then(function (result) {
        status(result.error ? (lang === "en" ? "Release failed." : "Die Freigabe ist fehlgeschlagen.") : (lang === "en" ? "Released entries: " : "Freigegebene Posten: ") + result.data, !!result.error);
        if (!result.error) loadCashback();
      });
    });
  });
})();
