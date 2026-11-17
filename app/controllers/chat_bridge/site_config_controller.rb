# frozen_string_literal: true

module ChatBridge
  # How the widget should look and behave on the site the request came from.
  #
  # Unauthenticated on purpose. Before this existed the appearance only arrived
  # with /session/me, so an administrator's colours and corner reached signed in
  # visitors alone, and everyone else saw the defaults. On a public website
  # nearly every visitor is signed out, which made the settings close to
  # decorative.
  #
  # Nothing here is private. It is exactly what the page shows to any visitor:
  # three colours, a corner, a title, a language and two switches. The site is
  # still resolved from the Origin header and never from the request body, like
  # every other endpoint, so a page can only ever ask about itself.
  class SiteConfigController < ChatBridge::BaseController
    skip_before_action :authenticate_bridge_token

    def show
      site = origin_site
      return render_bridge_error("unknown_site", 403) if site.nil?

      # Called once per page view, so the ceiling is set where a busy office
      # behind one address will not meet it. The widget treats a refusal like
      # any other failure and draws itself with the defaults.
      rate_limit_anonymous!("site_config", 240, 1.minute)
      return if performed?

      render_bridge_ok(site: { theme: site.theme_settings, features: site.feature_settings })
    end
  end
end
