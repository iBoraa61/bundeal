// Votes, comments and favorites for one published deal. No money is moved here.
(function () {
  var root = document.querySelector("[data-community]");
  if (!root || !window.bundealSupabase) return;
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" || document.documentElement.lang === "en" ? "en" : "de";
  var slug = params.get("slug") || "";
  var text = lang === "en"
    ? {
      temperature: "Recommendations",
      up: "Recommend",
      down: "Down",
      save: "Like",
      saved: "Saved",
      share: "Share",
      shared: "Link copied.",
      comments: "Comments",
      comment: "Comment",
      submit: "Save comment",
      report: "Report",
      empty: "No comments yet.",
      signIn: "Sign in to recommend, save or comment.",
      savedNote: "Comment saved.",
      reported: "Comment reported. It waits for review.",
      failed: "That was not saved.",
      limit: "The comment limit is reached."
    }
    : {
      temperature: "Empfehlungsanzahl",
      up: "Empfehlen",
      down: "Runter",
      save: "Gefällt mir",
      saved: "Gespeichert",
      share: "Teilen",
      shared: "Link kopiert.",
      comments: "Kommentare",
      comment: "Kommentar",
      submit: "Kommentar speichern",
      report: "Melden",
      empty: "Noch kein Kommentar.",
      signIn: "Zum Empfehlen, Speichern oder Kommentieren anmelden.",
      savedNote: "Kommentar gespeichert.",
      reported: "Kommentar gemeldet. Er wartet auf die Prüfung.",
      failed: "Das wurde nicht gespeichert.",
      limit: "Das Kommentarlimit ist erreicht."
    };

  function status(message, isError) {
    var element = document.querySelector("[data-deal-status]");
    if (!element) return;
    element.textContent = message || "";
    element.className = isError ? "form-error" : "status";
  }

  function reasonMessage(error) {
    var reason = error && error.message;
    if (reason === "sign in required") return text.signIn;
    if (reason === "comment limit") return text.limit;
    if (reason === "own comment") return text.failed;
    return text.failed;
  }

  function degreeLine(data) {
    var count = data && data.recommendations !== undefined && data.recommendations !== null
      ? Number(data.recommendations)
      : Math.max(0, Number(data && data.temperature) || 0);
    return text.temperature + " " + count;
  }

  function render(data) {
    var score = document.querySelector("[data-temperature]");
    if (score) score.textContent = degreeLine(data);
    root.querySelectorAll("[data-vote]").forEach(function (button) {
      var direction = Number(button.getAttribute("data-vote"));
      if (direction !== 1) {
        button.hidden = true;
        return;
      }
      button.hidden = false;
      button.classList.toggle("is-on", data && Number(data.my_vote) === 1);
      button.textContent = text.up;
    });
    var favorite = root.querySelector("[data-favorite]");
    if (favorite) {
      favorite.classList.toggle("is-on", !!(data && data.favorite));
      favorite.textContent = data && data.favorite ? text.saved : text.save;
    }
    var list = root.querySelector("[data-comments]");
    if (!list) return;
    var comments = (data && data.comments) || [];
    list.replaceChildren();
    if (!comments.length) {
      var empty = document.createElement("p");
      empty.textContent = text.empty;
      list.appendChild(empty);
      return;
    }
    comments.forEach(function (comment) {
      var article = document.createElement("article");
      article.className = "card";
      var title = document.createElement("h3");
      title.textContent = comment.author || "";
      var body = document.createElement("p");
      body.textContent = comment.body || "";
      article.appendChild(title);
      article.appendChild(body);
      if (!comment.mine) {
        var report = document.createElement("button");
        report.type = "button";
        report.className = "button button-secondary";
        report.textContent = text.report;
        report.addEventListener("click", function () {
          window.bundealSupabase.rpc("report_deal_comment", { p_comment_id: comment.id }).then(function (result) {
            status(result.error ? reasonMessage(result.error) : text.reported, !!result.error);
            if (!result.error) load();
          });
        });
        article.appendChild(report);
      }
      list.appendChild(article);
    });
  }

  function load() {
    return window.bundealSupabase.rpc("deal_community", { p_slug: slug }).then(function (result) {
      if (result.error || !result.data) return;
      render(result.data);
    });
  }

  root.querySelectorAll("h2").forEach(function (heading, index) {
    heading.textContent = index === 0 ? text.temperature : text.comments;
  });
  var label = root.querySelector("label");
  if (label) label.firstChild.textContent = text.comment + " ";
  var submit = root.querySelector("[data-comment-form] button");
  if (submit) submit.textContent = text.submit;

  root.querySelectorAll("[data-vote]").forEach(function (button) {
    button.addEventListener("click", function () {
      var direction = Number(button.getAttribute("data-vote"));
      var next = button.classList.contains("is-on") ? 0 : direction;
      window.bundealSupabase.rpc("cast_deal_vote", { p_slug: slug, p_direction: next }).then(function (result) {
        if (result.error) status(reasonMessage(result.error), true);
        else load();
      });
    });
  });
  var share = root.querySelector("[data-share]");
  if (share) share.textContent = text.share;
  if (share) share.addEventListener("click", function () {
    var url = window.location.href;
    function legacy() {
      var field = document.createElement("textarea");
      field.value = url;
      field.setAttribute("readonly", "");
      field.style.position = "fixed";
      field.style.left = "-999px";
      document.body.appendChild(field);
      field.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (error) { ok = false; }
      field.remove();
      return ok;
    }
    var copy = navigator.clipboard && navigator.clipboard.writeText
      ? navigator.clipboard.writeText(url).then(function () { return true; }).catch(function () { return legacy(); })
      : Promise.resolve(legacy());
    copy.then(function (ok) {
      if (ok) status(text.shared, false);
      else if (navigator.share) navigator.share({ url: url }).catch(function () {});
    });
  });
  var favorite = root.querySelector("[data-favorite]");
  if (favorite) favorite.addEventListener("click", function () {
    window.bundealSupabase.rpc("set_deal_favorite", {
      p_slug: slug,
      p_saved: !favorite.classList.contains("is-on")
    }).then(function (result) {
      if (result.error) status(reasonMessage(result.error), true);
      else load();
    });
  });
  var form = root.querySelector("[data-comment-form]");
  if (form) form.addEventListener("submit", function (event) {
    event.preventDefault();
    window.bundealSupabase.rpc("save_deal_comment", {
      p_slug: slug,
      p_body: form.body.value
    }).then(function (result) {
      status(result.error ? reasonMessage(result.error) : text.savedNote, !!result.error);
      if (!result.error) {
        form.reset();
        load();
      }
    });
  });
  if (slug) load();
})();
