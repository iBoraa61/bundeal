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

  var advertiserAnswers = [];

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
    var categorySelect = document.querySelector("[data-category-select]");
    if (categorySelect) {
      client().from("deal_categories").select("name,slug").order("name").then(function (result) {
        if (!result.data || !result.data.length) return;
        var current = categorySelect.value || "allgemein";
        categorySelect.replaceChildren();
        result.data.forEach(function (category) {
          var option = document.createElement("option");
          option.value = category.slug;
          option.textContent = category.name;
          categorySelect.appendChild(option);
        });
        categorySelect.value = current;
      });
    }
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

  function offerName(value) {
    if (value === "listing") return lang === "en" ? "Deal" : "Deal";
    if (value === "cashback") return "Cashback";
    if (value === "creator") return "Creator";
    return lang === "en" ? "Referral" : "Empfehlung";
  }

  function offerChoices() {
    return ["listing", "cashback", "referral", "creator"];
  }

  function loadMerchantCapabilities() {
    var list = document.querySelector("[data-merchant-capabilities]");
    if (!list) return;
    client().from("merchants").select("id,name,listing_allowed,affiliate_tracking_allowed,cashback_allowed,referral_reward_allowed,creator_campaign_allowed,deal_creator_reward_allowed,approval_notes").order("name").then(function (result) {
      list.replaceChildren();
      (result.data || []).forEach(function (merchant) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = merchant.name;
        var notes = document.createElement("textarea");
        notes.value = merchant.approval_notes || "";
        notes.maxLength = 500;
        var fields = [
          ["listing_allowed", lang === "en" ? "Normal deal" : "Normaler Deal"],
          ["affiliate_tracking_allowed", "Tracking"],
          ["cashback_allowed", "Cashback"],
          ["referral_reward_allowed", lang === "en" ? "Referral" : "Empfehlung"],
          ["creator_campaign_allowed", "Creator"],
          ["deal_creator_reward_allowed", lang === "en" ? "Creator-of-deal note, not paid yet" : "Ersteller-Beteiligung merken, noch keine Auszahlung"]
        ];
        var boxes = {};
        article.appendChild(title);
        fields.forEach(function (field) {
          var label = document.createElement("label");
          var input = document.createElement("input");
          input.type = "checkbox";
          input.checked = !!merchant[field[0]];
          boxes[field[0]] = input;
          label.appendChild(input);
          label.appendChild(document.createTextNode(" " + field[1]));
          article.appendChild(label);
        });
        article.appendChild(notes);
        var button = document.createElement("button");
        button.type = "button";
        button.className = "button button-secondary";
        button.textContent = lang === "en" ? "Save permissions" : "Freigaben speichern";
        button.addEventListener("click", function () {
          client().rpc("set_merchant_capabilities", {
            p_merchant_id: merchant.id,
            p_listing_allowed: boxes.listing_allowed.checked,
            p_affiliate_tracking_allowed: boxes.affiliate_tracking_allowed.checked,
            p_cashback_allowed: boxes.cashback_allowed.checked,
            p_referral_reward_allowed: boxes.referral_reward_allowed.checked,
            p_creator_campaign_allowed: boxes.creator_campaign_allowed.checked,
            p_deal_creator_reward_allowed: boxes.deal_creator_reward_allowed.checked,
            p_approval_notes: notes.value.trim() || null
          }).then(function (response) {
            status(response.error ? (lang === "en" ? "Permissions were not saved." : "Die Freigaben wurden nicht gespeichert.") : (lang === "en" ? "Permissions saved." : "Freigaben gespeichert."), !!response.error);
            if (!response.error) loadMerchantCapabilities();
          });
        });
        article.appendChild(button);
        list.appendChild(article);
      });
    });
  }

  function answerWord(value) {
    if (value === "yes") return lang === "en" ? "Yes" : "Ja";
    if (value === "no") return lang === "en" ? "No" : "Nein";
    return lang === "en" ? "Pending" : "Offen";
  }

  function checklistItem(text, ok) {
    var item = document.createElement("li");
    item.className = ok ? "is-ok" : "is-block";
    item.textContent = text;
    return item;
  }

  function renderPublishChecklist() {
    var form = document.querySelector("[data-deal-form]");
    var list = document.querySelector("[data-checklist-items]");
    if (!form || !list) return;
    var button = form.querySelector("button[type=submit]");
    var answer = advertiserAnswers.filter(function (row) {
      return row.merchant_id === form.merchant_id.value;
    })[0];
    var mode = form.offer_mode.value;
    list.replaceChildren();
    if (!answer) {
      list.appendChild(checklistItem(lang === "en"
        ? "No written answer for this merchant. Purchase is still not possible."
        : "Keine schriftliche Antwort für diesen Händler. Ein Kauf ist weiter nicht möglich.", true));
      if (button) button.disabled = false;
      return;
    }
    var needsCashback = mode === "cashback" || mode === "referral" || mode === "creator";
    var needsReferral = mode === "referral" || mode === "creator";
    var cashbackOk = !needsCashback || answer.cashback_answer === "yes";
    var referralOk = !needsReferral || answer.referral_answer === "yes";
    var confirmed = !!answer.owner_confirmed;
    list.appendChild(checklistItem((lang === "en" ? "Written cashback: " : "Schriftliches Cashback: ") + answerWord(answer.cashback_answer), cashbackOk));
    list.appendChild(checklistItem((lang === "en" ? "Written referral: " : "Schriftliche Empfehlung: ") + answerWord(answer.referral_answer), referralOk));
    list.appendChild(checklistItem(confirmed
      ? (lang === "en" ? "Partner matrix confirmed." : "Partner-Matrix bestätigt.")
      : (lang === "en" ? "Partner matrix is not confirmed yet." : "Partner-Matrix ist noch nicht bestätigt."), confirmed));
    list.appendChild(checklistItem(lang === "en"
      ? "Purchase is not possible yet. Tracking stays off."
      : "Kauf noch nicht möglich. Tracking bleibt aus.", true));
    if (button) button.disabled = !(cashbackOk && referralOk && confirmed);
  }

  function loadAdvertiserAnswers() {
    var list = document.querySelector("[data-advertiser-answers]");
    if (!list || !client()) return;
    client().from("advertiser_answers").select("merchant_id,cashback_answer,referral_answer,owner_confirmed,source_note").then(function (result) {
      if (result.error) {
        status(lang === "en" ? "The written answers could not be loaded." : "Die schriftlichen Antworten konnten nicht geladen werden.", true);
      }
      advertiserAnswers = result.data || [];
      return client().from("merchants").select("id,name").order("name");
    }).then(function (result) {
      var names = {};
      (result.data || []).forEach(function (merchant) {
        names[merchant.id] = merchant.name;
      });
      list.replaceChildren();
      if (!advertiserAnswers.length) {
        var empty = document.createElement("p");
        empty.textContent = lang === "en" ? "No written answer yet." : "Noch keine schriftliche Antwort.";
        list.appendChild(empty);
        renderPublishChecklist();
        return;
      }
      advertiserAnswers.slice().sort(function (a, b) {
        return (names[a.merchant_id] || "").localeCompare(names[b.merchant_id] || "", "de");
      }).forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = names[row.merchant_id] || "";
        var cashback = document.createElement("p");
        cashback.textContent = "Cashback: " + answerWord(row.cashback_answer);
        var referral = document.createElement("p");
        referral.textContent = (lang === "en" ? "Referral: " : "Empfehlung: ") + answerWord(row.referral_answer);
        var note = document.createElement("p");
        note.className = "fine";
        note.textContent = row.source_note || "";
        article.appendChild(title);
        article.appendChild(cashback);
        article.appendChild(referral);
        article.appendChild(note);
        if (row.owner_confirmed) {
          var done = document.createElement("p");
          done.textContent = lang === "en" ? "Matrix confirmed. Purchase is still not possible." : "Matrix bestätigt. Ein Kauf ist weiter nicht möglich.";
          article.appendChild(done);
        } else {
          var button = document.createElement("button");
          button.type = "button";
          button.className = "button button-secondary";
          button.textContent = lang === "en" ? "Confirm matrix" : "Matrix bestätigen";
          button.addEventListener("click", function () {
            client().rpc("confirm_advertiser_answer", { p_merchant_id: row.merchant_id }).then(function (response) {
              status(response.error
                ? (lang === "en" ? "The matrix was not confirmed." : "Die Matrix wurde nicht bestätigt.")
                : (lang === "en" ? "Matrix confirmed. Purchase is still not possible." : "Matrix bestätigt. Ein Kauf ist weiter nicht möglich."), !!response.error);
              if (!response.error) loadAdvertiserAnswers();
            });
          });
          article.appendChild(button);
        }
        list.appendChild(article);
      });
      renderPublishChecklist();
    });
  }

  function loadOfferModes() {
    var list = document.querySelector("[data-offer-modes]");
    if (!list) return;
    client().from("deals").select("id,title,offer_mode").eq("status", "published").order("title").then(function (result) {
      list.replaceChildren();
      if (!result.data || !result.data.length) {
        var empty = document.createElement("p");
        empty.textContent = lang === "en" ? "No published deal." : "Kein veröffentlichtes Angebot.";
        list.appendChild(empty);
        return;
      }
      result.data.forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card deal-card is-" + (row.offer_mode || "referral");
        var title = document.createElement("h3");
        title.textContent = row.title;
        var select = document.createElement("select");
        offerChoices().forEach(function (value) {
          var option = document.createElement("option");
          option.value = value;
          option.textContent = offerName(value);
          option.selected = row.offer_mode === value;
          select.appendChild(option);
        });
        var button = document.createElement("button");
        button.type = "button";
        button.className = "button button-secondary";
        button.textContent = lang === "en" ? "Save type" : "Art speichern";
        button.addEventListener("click", function () {
          client().rpc("set_deal_offer_mode", {
            p_deal_id: row.id,
            p_offer_mode: select.value
          }).then(function (response) {
            var reason = response.error && response.error.message;
            var message = !response.error
              ? (lang === "en" ? "Type saved." : "Art gespeichert.")
              : reason === "partner matrix not confirmed"
                ? (lang === "en" ? "The partner matrix is not confirmed yet." : "Die Partner-Matrix ist noch nicht bestätigt.")
                : reason === "cashback not approved"
                  ? (lang === "en" ? "Cashback is not approved in writing." : "Cashback ist schriftlich nicht freigegeben.")
                  : reason === "referral not approved"
                    ? (lang === "en" ? "A referral is not approved in writing." : "Eine Empfehlung ist schriftlich nicht freigegeben.")
                    : reason === "offer mode not allowed"
                      ? (lang === "en" ? "This merchant does not allow that offer type." : "Dieser Händler hat diese Angebotsart nicht freigegeben.")
                      : (lang === "en" ? "The type was not saved." : "Die Art wurde nicht gespeichert.");
            status(message, !!response.error);
            if (!response.error) loadOfferModes();
          });
        });
        article.appendChild(title);
        var current = document.createElement("p");
        current.className = "offer-pill is-" + (row.offer_mode || "referral");
        current.textContent = offerName(row.offer_mode);
        article.appendChild(current);
        article.appendChild(select);
        article.appendChild(button);
        list.appendChild(article);
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
        var mode = document.createElement("select");
        mode.innerHTML = lang === "en"
          ? "<option value=\"listing\" selected>Deal</option><option value=\"cashback\">Cashback</option><option value=\"referral\">Referral</option><option value=\"creator\">Creator</option>"
          : "<option value=\"listing\" selected>Deal</option><option value=\"cashback\">Cashback</option><option value=\"referral\">Empfehlung</option><option value=\"creator\">Creator</option>";
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
            p_currency: row.currency || "EUR",
            p_offer_mode: mode.value
          }).then(function (response) {
            status(response.error ? (lang === "en" ? "Review failed." : "Die Prüfung ist fehlgeschlagen.") : (lang === "en" ? "Suggestion published." : "Vorschlag veröffentlicht."), !!response.error);
            if (!response.error) {
              loadSubmissions();
              loadMerchants();
              loadOfferModes();
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
        article.appendChild(mode);
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

  function loadImportRuns() {
    var list = document.querySelector("[data-import-runs]");
    if (!list) return;
    client().from("import_runs").select("environment,status,row_count,ready_count,inserted_count,duplicate_count,unattributed_count,invalid_count,created_at").order("created_at", { ascending: false }).limit(8).then(function (result) {
      fillCards("[data-import-runs]", result.data || [], function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.status + " · " + row.environment;
        var body = document.createElement("p");
        body.textContent = (lang === "en" ? "Rows " : "Zeilen ") + row.row_count
          + (lang === "en" ? " · stored " : " · gespeichert ") + row.inserted_count
          + (lang === "en" ? " · unmatched " : " · ohne Klick ") + row.unattributed_count
          + (lang === "en" ? " · invalid " : " · ungültig ") + row.invalid_count
          + " · " + stamp(row.created_at);
        article.appendChild(title);
        article.appendChild(body);
        return article;
      });
    });
  }

  function loadPayoutMarkers() {
    var list = document.querySelector("[data-payout-markers]");
    if (!list) return;
    client().from("payout_markers").select("environment,amount_cents,reference_note,created_at").order("created_at", { ascending: false }).limit(8).then(function (result) {
      var rows = result.data || [];
      list.replaceChildren();
      if (!rows.length) {
        var empty = document.createElement("p");
        empty.textContent = lang === "en" ? "No payout recorded. Nothing is transferred from here." : "Keine Auszahlung erfasst. Von hier wird nichts überwiesen.";
        list.appendChild(empty);
        return;
      }
      rows.forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.environment + " · " + euros(row.amount_cents);
        var body = document.createElement("p");
        body.textContent = row.reference_note + " · " + stamp(row.created_at);
        article.appendChild(title);
        article.appendChild(body);
        list.appendChild(article);
      });
    });
  }

  function loadCommunityQueue() {
    var list = document.querySelector("[data-community-queue]");
    if (!list || !client()) return;
    client().rpc("community_queue").then(function (result) {
      var rows = result.data || [];
      list.replaceChildren();
      if (!rows.length) {
        var empty = document.createElement("p");
        empty.textContent = lang === "en" ? "No comment is waiting." : "Kein Kommentar wartet.";
        list.appendChild(empty);
        return;
      }
      rows.forEach(function (row) {
        var article = document.createElement("article");
        article.className = "card";
        var title = document.createElement("h3");
        title.textContent = row.deal_title + " · " + row.status;
        var author = document.createElement("p");
        author.textContent = row.author || "";
        var body = document.createElement("p");
        body.textContent = row.body || "";
        var button = document.createElement("button");
        button.type = "button";
        button.className = "button button-secondary";
        var next = row.status === "hidden" ? "visible" : "hidden";
        button.textContent = next === "hidden"
          ? (lang === "en" ? "Hide" : "Ausblenden")
          : (lang === "en" ? "Show again" : "Wieder zeigen");
        button.addEventListener("click", function () {
          client().rpc("moderate_deal_comment", { p_comment_id: row.id, p_status: next }).then(function (response) {
            status(response.error ? (lang === "en" ? "The comment was not changed." : "Der Kommentar wurde nicht geändert.") : (lang === "en" ? "Comment updated." : "Kommentar geändert."), !!response.error);
            if (!response.error) loadCommunityQueue();
          });
        });
        article.appendChild(title);
        article.appendChild(author);
        article.appendChild(body);
        article.appendChild(button);
        list.appendChild(article);
      });
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
      loadImportRuns();
      loadPayoutMarkers();
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
    loadMerchantCapabilities();
    loadAdvertiserAnswers();
    loadCommunityQueue();
    loadOfferModes();
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
          loadMerchantCapabilities();
        }
      });
    });
    var dealForm = document.querySelector("[data-deal-form]");
    dealForm.merchant_id.addEventListener("change", renderPublishChecklist);
    dealForm.offer_mode.addEventListener("change", renderPublishChecklist);
    renderPublishChecklist();
    dealForm.addEventListener("submit", function (event) {
      event.preventDefault();
      var form = event.currentTarget;
      var image = form.image.value.trim();
      var price = Number(form.price.value);
      var originalText = form.original_price.value.trim();
      var original = originalText ? Number(originalText) : null;
      if (image && (image.length < 12 || image.length > 1000 || !/^https:\/\/[^\s<>"'\\@#]+$/.test(image))) {
        status(lang === "en" ? "The image address must be https." : "Die Bildadresse muss https sein.", true);
        return;
      }
      if (originalText && (!Number.isInteger(original) || original < price)) {
        status(lang === "en" ? "The previous shop price must be at least the current price." : "Der vorherige Shop-Preis muss mindestens der aktuelle Preis sein.", true);
        return;
      }
      client().rpc("create_published_deal", {
        p_merchant_id: form.merchant_id.value,
        p_category_slug: form.category_slug.value,
        p_slug: form.slug.value.trim(),
        p_title: form.title.value.trim(),
        p_description: form.description.value.trim(),
        p_price_cents: price,
        p_currency: "EUR",
        p_image_url: image || null,
        p_offer_mode: form.offer_mode.value,
        p_original_price_cents: original
      }).then(function (result) {
        var reason = result.error && result.error.message;
        var saved = !result.error;
        var message = saved
          ? (lang === "en" ? "Deal published. Purchase is still not possible." : "Deal veröffentlicht. Ein Kauf ist weiter nicht möglich.")
          : reason === "partner matrix not confirmed"
            ? (lang === "en" ? "The partner matrix is not confirmed yet." : "Die Partner-Matrix ist noch nicht bestätigt.")
            : reason === "cashback not approved"
              ? (lang === "en" ? "Cashback is not approved in writing." : "Cashback ist schriftlich nicht freigegeben.")
              : reason === "referral not approved"
                ? (lang === "en" ? "A referral is not approved in writing." : "Eine Empfehlung ist schriftlich nicht freigegeben.")
                : reason === "offer mode not allowed"
                  ? (lang === "en" ? "This merchant does not allow that offer type." : "Dieser Händler hat diese Angebotsart nicht freigegeben.")
                  : (lang === "en" ? "Deal was not published." : "Der Deal wurde nicht veröffentlicht.");
        status(message, !saved);
        if (!result.error) {
          form.reset();
          loadMerchants();
          loadOfferModes();
          renderPublishChecklist();
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
    var awinForm = document.querySelector("[data-awin-form]");
    if (awinForm) awinForm.addEventListener("submit", function (event) {
      event.preventDefault();
      client().rpc("import_awin_rows", {
        p_rows: [
          { id: "awin-1001", clickRef: "sampleclick0001", commissionStatus: "approved", commissionAmount: "10.50", saleAmount: "100.00", currency: "EUR", transactionDate: "2026-11-02T10:00:00Z" },
          { id: "awin-1002", clickRef: "sampleclick0002", commissionStatus: "pending", commissionAmount: "2.00", saleAmount: "20.00", currency: "EUR", transactionDate: "2026-11-03T10:00:00Z" },
          { id: "awin-1003", clickRef: "sampleclick0003", commissionStatus: "bonus", commissionAmount: "1.00", saleAmount: "5.00", currency: "EUR", transactionDate: "2026-11-04T10:00:00Z" }
        ],
        p_environment: "simulation",
        p_apply: false,
        p_account_reference: "dev"
      }).then(function (result) {
        if (result.error) {
          status(lang === "en" ? "The Awin dry-run failed." : "Der Awin-Probelauf ist fehlgeschlagen.", true);
          return;
        }
        var data = result.data || {};
        status((lang === "en" ? "Dry-run only. Unmatched " : "Nur Probelauf. Ohne Klick ") + (data.unattributed_count || 0)
          + (lang === "en" ? ", invalid " : ", ungültig ") + (data.invalid_count || 0)
          + (lang === "en" ? ". Nothing was booked." : ". Nichts wurde gebucht."), false);
        loadImportRuns();
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
