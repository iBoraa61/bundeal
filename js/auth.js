// Account pages. The session stays in the Supabase client storage (localStorage).
// This file never reads a privileged server key and never sends a role or referral code.
(function () {
  var utils = window.bundealUtils;
  var params = new URLSearchParams(window.location.search);
  var lang = params.get("lang") === "en" ? "en" : "de";
  var page = document.body.getAttribute("data-auth-page");
  var copy = {
    de: {
      proto: "Prototyp. Die Angebote sind Beispiele. Ein Kauf ist über BunDeal noch nicht möglich.",
      skip: "Zum Inhalt",
      navProcess: "Ablauf",
      navExample: "Beispiel",
      navAccount: "Anmelden",
      navLegal: "Impressum",
      loginEyebrow: "Konto",
      loginTitle: "Anmelden",
      loginLead: "Melde dich an, bevor du später einen Händler-Link öffnest. Cashback wird hier noch nicht berechnet.",
      email: "E-Mail",
      password: "Passwort",
      loginSubmit: "Anmelden",
      loginFailed: "E-Mail oder Passwort ist nicht richtig.",
      missingConfig: "Anmeldung ist in dieser öffentlichen Vorschau noch nicht angebunden.",
      goRegister: "Konto anlegen",
      goReset: "Passwort vergessen",
      goLogin: "Zur Anmeldung",
      registerEyebrow: "Konto",
      registerTitle: "Konto anlegen",
      registerLead: "Der Empfehlungscode entsteht auf dem Server. Eine Creator-Rolle gilt erst nach Prüfung.",
      creatorApply: "Ich möchte als Creator geprüft werden",
      creatorChannel: "Kanal",
      creatorHint: "Zum Beispiel ein Kanalname. Die Rolle gilt erst nach Prüfung in der Verwaltung. Eine E-Mail gehört hier nicht hin.",
      username: "Nutzername",
      usernameHint: "Optional. 3 bis 30 Zeichen: Kleinbuchstaben, Zahlen und Unterstrich.",
      displayName: "Anzeigename",
      displayNameHint: "Optional, höchstens 80 Zeichen.",
      passwordAgain: "Passwort wiederholen",
      registerSubmit: "Konto anlegen",
      passwordShort: "Das Passwort braucht mindestens 8 Zeichen.",
      passwordMismatch: "Die Passwörter stimmen nicht überein.",
      usernameInvalid: "Der Nutzername braucht 3 bis 30 Zeichen aus Kleinbuchstaben, Zahlen und Unterstrich.",
      displayNameInvalid: "Der Anzeigename darf höchstens 80 Zeichen haben.",
      usernameTaken: "Dieser Nutzername ist ungültig oder schon vergeben.",
      alreadyRegistered: "Für diese E-Mail gibt es schon ein Konto.",
      registerConfirm: "Prüfe dein Postfach und bestätige die E-Mail. Danach kannst du dich anmelden.",
      registerFailed: "Das Konto konnte nicht angelegt werden.",
      resetEyebrow: "Konto",
      resetTitle: "Passwort zurücksetzen",
      resetLead: "Der Link führt nur auf eine hinterlegte Adresse dieser Website zurück.",
      resetSubmit: "Link senden",
      resetSent: "Wenn ein Konto zu dieser E-Mail besteht, ist der Link unterwegs. Lokal liegt die Nachricht in Mailpit.",
      resetFailed: "Der Link konnte nicht angefordert werden.",
      originNotAllowed: "Öffne die Seite über http://127.0.0.1:4173 oder https://bundeal.de, damit der Link erlaubt ist.",
      newPasswordTitle: "Neues Passwort",
      newPasswordLead: "Lege ein neues Passwort mit mindestens 8 Zeichen fest.",
      newPasswordSubmit: "Passwort speichern",
      passwordSaved: "Das Passwort ist gespeichert.",
      passwordSaveFailed: "Das Passwort konnte nicht gespeichert werden.",
      dashboardEyebrow: "Konto",
      dashboardTitle: "Dein Konto",
      dashboardLead: "Dein Cashback, deine Empfehlungen und deine Vorschläge. Eine Auszahlung gibt es hier noch nicht. Ein Betrag auf der Dealseite ist eine Schätzung und kein Guthaben.",
      roleCreator: "Creator",
      emailLabel: "E-Mail",
      roleLabel: "Rolle",
      roleUser: "Nutzer",
      roleAdmin: "Admin",
      referralLabel: "Empfehlungscode",
      referralHint: "Der Code bleibt fest und wird auf dem Server erzeugt.",
      saveProfile: "Angaben speichern",
      profileSaved: "Die Angaben sind gespeichert.",
      profileFailed: "Die Angaben konnten nicht gespeichert werden.",
      logout: "Abmelden",
      noUsername: "noch nicht gewählt",
      laterTitle: "Noch nicht in dieser Phase",
      laterBody: "Hier gibt es noch kein Cashback, keine Empfehlungsstatistik und keine Auszahlung.",
      sessionHint: "Du bist angemeldet.",
      goDashboard: "Zum Konto",
      devNotice: "Entwicklungsumgebung. Es werden keine echten Auszahlungen ausgeführt.",
      copyCode: "Code kopieren",
      codeCopied: "Code kopiert.",
      loading: "Konto wird geladen.",
      accountLink: "Konto",
      footerExample: "Beispiel-Deal",
      footerLegal: "Impressum",
      footerPrivacy: "Datenschutz"
    },
    en: {
      proto: "Prototype. All offers are examples. Purchases through BunDeal are not yet available.",
      skip: "Skip to content",
      navProcess: "Process",
      navExample: "Example",
      navAccount: "Sign in",
      navLegal: "Legal notice",
      loginEyebrow: "Account",
      loginTitle: "Sign in",
      loginLead: "Sign in before you later open a merchant link. Cashback is not calculated in this phase.",
      email: "Email",
      password: "Password",
      loginSubmit: "Sign in",
      loginFailed: "The email or password is not correct.",
      missingConfig: "Sign-in is not connected in this public preview yet.",
      goRegister: "Create account",
      goReset: "Forgot password",
      goLogin: "Back to sign in",
      registerEyebrow: "Account",
      registerTitle: "Create account",
      registerLead: "The referral code is created on the server. A creator role starts only after review.",
      creatorApply: "I want to be reviewed as a creator",
      creatorChannel: "Channel",
      creatorHint: "For example a channel name. The role starts only after review. Do not put an email here.",
      username: "Username",
      usernameHint: "Optional. 3 to 30 characters: lowercase letters, digits and underscore.",
      displayName: "Display name",
      displayNameHint: "Optional, at most 80 characters.",
      passwordAgain: "Repeat password",
      registerSubmit: "Create account",
      passwordShort: "The password needs at least 8 characters.",
      passwordMismatch: "The passwords do not match.",
      usernameInvalid: "The username needs 3 to 30 lowercase letters, digits or underscores.",
      displayNameInvalid: "The display name can have at most 80 characters.",
      usernameTaken: "This username is invalid or already taken.",
      alreadyRegistered: "An account already exists for this email.",
      registerConfirm: "Check your inbox and confirm the email. You can sign in afterwards.",
      registerFailed: "The account could not be created.",
      resetEyebrow: "Account",
      resetTitle: "Reset password",
      resetLead: "The link only returns to an allowlisted address of this website.",
      resetSubmit: "Send link",
      resetSent: "If an account exists for this email, the link is on its way. Locally it arrives in Mailpit.",
      resetFailed: "The link could not be requested.",
      originNotAllowed: "Open this page through http://127.0.0.1:4173 or https://bundeal.de so the link is allowed.",
      newPasswordTitle: "New password",
      newPasswordLead: "Choose a new password with at least 8 characters.",
      newPasswordSubmit: "Save password",
      passwordSaved: "The password is saved.",
      passwordSaveFailed: "The password could not be saved.",
      dashboardEyebrow: "Account",
      dashboardTitle: "Your account",
      dashboardLead: "Your cashback, referrals and suggestions. There is no payout here yet. An amount on a deal page is an estimate, not a balance.",
      roleCreator: "Creator",
      emailLabel: "Email",
      roleLabel: "Role",
      roleUser: "User",
      roleAdmin: "Admin",
      referralLabel: "Referral code",
      referralHint: "The code stays fixed and is created on the server.",
      saveProfile: "Save details",
      profileSaved: "The details are saved.",
      profileFailed: "The details could not be saved.",
      logout: "Log out",
      noUsername: "not chosen yet",
      laterTitle: "Not in this phase",
      laterBody: "There is no cashback, referral statistic or payout here yet.",
      sessionHint: "You are signed in.",
      goDashboard: "Go to account",
      devNotice: "Development environment. No real payouts are made.",
      copyCode: "Copy code",
      codeCopied: "Code copied.",
      loading: "Loading account.",
      accountLink: "Account",
      footerExample: "Example deal",
      footerLegal: "Legal notice",
      footerPrivacy: "Privacy"
    }
  };

  function t(key) {
    return (copy[lang] && copy[lang][key]) || key;
  }

  function withLang(pageName) {
    if (lang !== "en") return pageName;
    return pageName + (pageName.indexOf("?") === -1 ? "?lang=en" : "&lang=en");
  }

  function applyI18n() {
    document.documentElement.lang = lang;
    document.title = t(page + "Title") + " – BunDeal";
    document.querySelectorAll("[data-i18n]").forEach(function (element) {
      element.textContent = t(element.getAttribute("data-i18n"));
    });
    document.querySelectorAll("[data-href-de]").forEach(function (element) {
      var href = lang === "en" ? element.getAttribute("data-href-en") : element.getAttribute("data-href-de");
      if (href) element.setAttribute("href", href);
    });
    var languageSwitch = document.querySelector("[data-language-switch]");
    var currentPage = window.location.pathname.split("/").pop() || "login.html";
    if (languageSwitch) {
      if (lang === "en") {
        languageSwitch.textContent = "DE";
        languageSwitch.setAttribute("href", currentPage);
        languageSwitch.lang = "de";
        languageSwitch.setAttribute("aria-label", "Zur deutschen Sprache");
      } else {
        languageSwitch.textContent = "EN";
        languageSwitch.setAttribute("href", currentPage + "?lang=en");
        languageSwitch.lang = "en";
        languageSwitch.setAttribute("aria-label", "Switch to English");
      }
    }
  }

  function client() {
    return window.bundealSupabase || null;
  }

  function setStatus(element, message, isError) {
    if (!element) return;
    element.textContent = message || "";
    element.className = isError ? "form-error" : "status";
  }

  function requireClient(statusElement) {
    if (client()) return true;
    setStatus(statusElement, t("missingConfig"), true);
    return false;
  }

  function showDevNotice() {
    var notice = document.querySelector("[data-dev-notice]");
    var config = window.BUNDEAL_SUPABASE;
    if (notice && config && config.environment === "development") notice.hidden = false;
  }

  function passwordChecks(password, repeated) {
    if (!password || password.length < 8) return t("passwordShort");
    if (repeated !== undefined && password !== repeated) return t("passwordMismatch");
    return "";
  }

  function mapSignUpError(error) {
    var message = String((error && error.message) || "").toLowerCase();
    if (message.indexOf("already") !== -1 || message.indexOf("registered") !== -1) return t("alreadyRegistered");
    if (message.indexOf("username") !== -1 || message.indexOf("duplicate") !== -1 || message.indexOf("unique") !== -1) return t("usernameTaken");
    if (message.indexOf("creator request") !== -1) return t("creatorHint");
    if (message.indexOf("password") !== -1) return t("passwordShort");
    return t("registerFailed");
  }

  function bindLogin() {
    var form = document.querySelector("[data-auth-form='login']");
    var statusElement = document.querySelector("[data-auth-status]");
    if (!form) return;
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (!requireClient(statusElement)) return;
      var button = form.querySelector("button");
      button.disabled = true;
      client().auth.signInWithPassword({
        email: form.email.value.trim(),
        password: form.password.value
      }).then(function (result) {
        button.disabled = false;
        if (result.error || !result.data.session) {
          setStatus(statusElement, t("loginFailed"), true);
          return;
        }
        var nextPage = utils.safeNext(params.get("next"));
        var dealSlug = utils.safeSlug(params.get("slug"));
        var referralCode = params.get("ref") || "";
        if (nextPage === "deal.html" && dealSlug) {
          nextPage = "deal.html?slug=" + encodeURIComponent(dealSlug);
          if (/^[a-z0-9]{10}$/.test(referralCode)) nextPage += "&ref=" + encodeURIComponent(referralCode);
          var campaignCode = params.get("c") || "";
          if (/^[a-z0-9]{10}$/.test(campaignCode)) nextPage += "&c=" + encodeURIComponent(campaignCode);
        }
        window.location.assign(withLang(nextPage));
      }).catch(function () {
        button.disabled = false;
        setStatus(statusElement, t("loginFailed"), true);
      });
    });
  }

  function bindRegister() {
    var form = document.querySelector("[data-auth-form='register']");
    var statusElement = document.querySelector("[data-auth-status]");
    if (!form) return;
    var creatorToggle = form.querySelector("[name='creatorRequest']");
    var creatorChannel = form.querySelector("[data-creator-channel]");
    if (creatorToggle && creatorChannel) {
      creatorToggle.addEventListener("change", function () {
        creatorChannel.hidden = !creatorToggle.checked;
        var field = creatorChannel.querySelector("textarea");
        if (field) field.required = creatorToggle.checked;
      });
    }
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (!requireClient(statusElement)) return;
      var username = form.username.value.trim().toLowerCase();
      var displayName = form.displayName.value.trim();
      var passwordError = passwordChecks(form.password.value, form.password2.value);
      if (passwordError) {
        setStatus(statusElement, passwordError, true);
        return;
      }
      if (utils.usernameError(username)) {
        setStatus(statusElement, t("usernameInvalid"), true);
        return;
      }
      if (utils.displayNameError(displayName)) {
        setStatus(statusElement, t("displayNameInvalid"), true);
        return;
      }

      var metadata = {};
      if (username) metadata.username = username;
      if (displayName) metadata.display_name = displayName;
      if (form.creatorRequest && form.creatorRequest.checked) {
        var channel = form.channel.value.trim();
        if (channel.length < 8 || channel.length > 160) {
          setStatus(statusElement, t("creatorHint"), true);
          return;
        }
        metadata.creator_request = channel;
      }
      var options = { data: metadata };
      var emailRedirect = utils.callbackUrl(window.location.origin, "login.html");
      if (emailRedirect) options.emailRedirectTo = emailRedirect;

      var button = form.querySelector("button");
      button.disabled = true;
      client().auth.signUp({
        email: form.email.value.trim(),
        password: form.password.value,
        options: options
      }).then(function (result) {
        button.disabled = false;
        if (result.error) {
          setStatus(statusElement, mapSignUpError(result.error), true);
          return;
        }
        if (result.data.session) {
          window.location.assign(withLang("dashboard.html"));
          return;
        }
        setStatus(statusElement, t("registerConfirm"), false);
      }).catch(function () {
        button.disabled = false;
        setStatus(statusElement, t("registerFailed"), true);
      });
    });
  }

  function showNewPasswordForm() {
    var requestForm = document.querySelector("[data-auth-form='recover']");
    var newForm = document.querySelector("[data-auth-form='new-password']");
    if (requestForm) requestForm.hidden = true;
    if (newForm) newForm.hidden = false;
  }

  function bindReset() {
    var requestForm = document.querySelector("[data-auth-form='recover']");
    var newForm = document.querySelector("[data-auth-form='new-password']");
    var statusElement = document.querySelector("[data-auth-status]");
    var sessionHint = document.querySelector("[data-session-hint]");
    if (!requestForm || !newForm) return;
    if (!requireClient(statusElement)) return;

    var recovery = window.location.hash.indexOf("type=recovery") !== -1;
    client().auth.onAuthStateChange(function (event, session) {
      if (event === "PASSWORD_RECOVERY") {
        recovery = true;
        showNewPasswordForm();
      }
      if (session && sessionHint && !recovery) sessionHint.hidden = false;
    });

    requestForm.addEventListener("submit", function (event) {
      event.preventDefault();
      var redirectTo = utils.callbackUrl(window.location.origin, "reset-password.html");
      if (!redirectTo) {
        setStatus(statusElement, t("originNotAllowed"), true);
        return;
      }
      var button = requestForm.querySelector("button");
      button.disabled = true;
      client().auth.resetPasswordForEmail(requestForm.email.value.trim(), {
        redirectTo: redirectTo
      }).then(function (result) {
        button.disabled = false;
        if (result.error) {
          setStatus(statusElement, t("resetFailed"), true);
          return;
        }
        setStatus(statusElement, t("resetSent"), false);
      }).catch(function () {
        button.disabled = false;
        setStatus(statusElement, t("resetFailed"), true);
      });
    });

    newForm.addEventListener("submit", function (event) {
      event.preventDefault();
      var passwordError = passwordChecks(newForm.password.value, newForm.password2.value);
      if (passwordError) {
        setStatus(statusElement, passwordError, true);
        return;
      }
      var button = newForm.querySelector("button");
      button.disabled = true;
      client().auth.updateUser({ password: newForm.password.value }).then(function (result) {
        button.disabled = false;
        if (result.error) {
          setStatus(statusElement, t("passwordSaveFailed"), true);
          return;
        }
        setStatus(statusElement, t("passwordSaved"), false);
        window.setTimeout(function () {
          window.location.assign(withLang("dashboard.html"));
        }, 600);
      }).catch(function () {
        button.disabled = false;
        setStatus(statusElement, t("passwordSaveFailed"), true);
      });
    });
  }

  function bindDashboard() {
    var statusElement = document.querySelector("[data-auth-status]");
    var form = document.querySelector("[data-auth-form='profile']");
    if (!form) return;
    if (!requireClient(statusElement)) return;
    setStatus(statusElement, t("loading"), false);

    client().auth.getSession().then(function (result) {
      var session = result.data.session;
      if (!session) {
        window.location.assign(withLang("login.html") + (lang === "en" ? "&next=dashboard.html" : "?next=dashboard.html"));
        return;
      }
      return loadDashboard(session);
    }).catch(function () {
      setStatus(statusElement, t("profileFailed"), true);
    });

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var username = form.username.value.trim().toLowerCase();
      var displayName = form.displayName.value.trim();
      if (utils.usernameError(username)) {
        setStatus(statusElement, t("usernameInvalid"), true);
        return;
      }
      if (utils.displayNameError(displayName)) {
        setStatus(statusElement, t("displayNameInvalid"), true);
        return;
      }
      var button = form.querySelector("[data-save-profile]");
      button.disabled = true;
      client().auth.getSession().then(function (result) {
        var session = result.data.session;
        if (!session) {
          window.location.assign(lang === "en" ? "login.html?lang=en&next=dashboard.html" : "login.html?next=dashboard.html");
          return null;
        }
        return client().from("profiles").update({
          username: username || null,
          display_name: displayName || null
        }).eq("id", session.user.id);
      }).then(function (updateResult) {
        button.disabled = false;
        if (!updateResult) return;
        if (updateResult.error) {
          var updateMessage = String(updateResult.error.message || "").toLowerCase();
          var usernameTaken = updateMessage.indexOf("unique") !== -1 || updateMessage.indexOf("duplicate") !== -1 || updateMessage.indexOf("username") !== -1;
          setStatus(statusElement, usernameTaken ? t("usernameTaken") : t("profileFailed"), true);
          return;
        }
        setStatus(statusElement, t("profileSaved"), false);
        if (window.bundealRefreshAccountMenu) window.bundealRefreshAccountMenu();
      }).catch(function () {
        button.disabled = false;
        setStatus(statusElement, t("profileFailed"), true);
      });
    });

    var logout = document.querySelector("[data-logout]");
    if (logout) {
      logout.addEventListener("click", function () {
        client().auth.signOut().then(function () {
          window.location.assign(withLang("login.html"));
        });
      });
    }

    var copyButton = document.querySelector("[data-copy-code]");
    if (copyButton) {
      copyButton.addEventListener("click", function () {
        var code = document.querySelector("[data-referral-code]");
        var value = code ? code.value : "";
        if (!value || !navigator.clipboard) return;
        navigator.clipboard.writeText(value).then(function () {
          setStatus(statusElement, t("codeCopied"), false);
        });
      });
    }
  }

  function loadDashboard(session) {
    var statusElement = document.querySelector("[data-auth-status]");
    var form = document.querySelector("[data-auth-form='profile']");
    var email = document.querySelector("[data-account-email]");
    var role = document.querySelector("[data-account-role]");
    var referral = document.querySelector("[data-referral-code]");
    var accountLink = document.querySelector("[data-account-link]");
    if (email) email.textContent = session.user.email || "";
    if (accountLink) {
      accountLink.textContent = t("accountLink");
      accountLink.setAttribute("href", withLang("dashboard.html"));
      accountLink.setAttribute("aria-current", "page");
    }

    return Promise.all([
      client().from("profiles").select("username, display_name, referral_code").eq("id", session.user.id).maybeSingle(),
      client().from("user_roles").select("role").eq("user_id", session.user.id)
    ]).then(function (results) {
      var profileResult = results[0];
      var roleResult = results[1];
      if (profileResult.error || !profileResult.data) {
        setStatus(statusElement, t("profileFailed"), true);
        return;
      }
      form.username.value = profileResult.data.username || "";
      form.displayName.value = profileResult.data.display_name || "";
      if (referral) referral.value = profileResult.data.referral_code || "";
      var roles = roleResult.data || [];
      var isAdmin = roles.some(function (entry) { return entry.role === "admin"; });
      var isCreator = roles.some(function (entry) { return entry.role === "creator"; });
      if (role) role.textContent = isAdmin ? t("roleAdmin") : (isCreator ? t("roleCreator") : t("roleUser"));
      setStatus(statusElement, "", false);
    });
  }

  applyI18n();
  showDevNotice();
  if (page === "login") bindLogin();
  if (page === "register") bindRegister();
  if (page === "reset") bindReset();
  if (page === "dashboard") bindDashboard();
})();
