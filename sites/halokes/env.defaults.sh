# Sourced by scripts/render-env.sh before rendering. Optional HALOKES_* variables.
# Login-page quick-fill for demo accounts: off unless HALOKES_DEMO_LOGIN_HINTS=true (a repository variable).
# The password in HALOKES_DEMO_LOGIN_PASSWORD (a secret) is then shown to every visitor of the login page.
export HALOKES_DEMO_LOGIN_HINTS=${HALOKES_DEMO_LOGIN_HINTS:-false}
export HALOKES_DEMO_LOGIN_PASSWORD=${HALOKES_DEMO_LOGIN_PASSWORD:-}
