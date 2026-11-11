// Initializes the public Supabase client only when development config is present.
// Financial and administrative operations do not belong in this file.
(function () {
  var config = window.BUNDEAL_SUPABASE;

  function isConfigured(value) {
    return value &&
      value.url &&
      value.publishableKey &&
      value.url.indexOf("YOUR_DEV_PROJECT") === -1 &&
      value.publishableKey.indexOf("YOUR_DEV_PUBLISHABLE_KEY") === -1;
  }

  if (!isConfigured(config)) {
    window.bundealSupabase = null;
    return;
  }

  if (!window.supabase || !window.supabase.createClient) {
    window.bundealSupabase = null;
    return;
  }

  window.bundealSupabase = window.supabase.createClient(
    config.url,
    config.publishableKey,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    }
  );
})();
