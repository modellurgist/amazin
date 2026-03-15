# V14 Dual+Signals Credo configuration
#
# Copy this file to amazin/.credo.exs when running the V14 variant,
# or have switch.sh copy it automatically.
#
# This configuration enforces:
# 1. Vertical ALA layer boundaries (existing rule)
# 2. Horizontal UI↔Domain machine independence
# 3. Signal flow direction (domain→UI only)
# 4. Typed outcome constructors over raw tuples
# 5. Thin LiveView shell (no domain logic in LiveView)

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: [
        "lib/amazin/credo/ala_layer_boundary.ex",
        "lib/amazin/credo/v14_horizontal_coupling.ex",
        "lib/amazin/credo/v14_signal_discipline.ex",
        "lib/amazin/credo/v14_outcome_constructor.ex",
        "lib/amazin/credo/v14_liveview_thin_shell.ex"
      ],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # ── 1. Vertical ALA layer boundaries ──────────────────────────
          #
          # Domain modules: no persistence, no Phoenix, no framework.
          # UI machines: no persistence, no Phoenix, no framework.
          # Foundation: no upward deps into Domain/UI/Pages.
          #
          {Credo.Check.Custom.AlaLayerBoundary, [
            layers: [
              %{
                name: "Domain",
                path: "lib/amazin/domain/",
                forbidden_prefixes: [
                  "Amazin.Foundation",
                  "Amazin.Pages",
                  "Amazin.Actions",
                  "Amazin.UI",
                  "AmazinWeb",
                  "Phoenix",
                  "Ecto.Repo",
                  "Ecto.Query",
                  "Ecto.Changeset"
                ]
              },
              %{
                name: "UI Machines",
                path: "lib/amazin/ui/",
                forbidden_prefixes: [
                  "Amazin.Foundation",
                  "Amazin.Domain",
                  "AmazinWeb",
                  "Phoenix",
                  "Ecto"
                ]
              },
              %{
                name: "Foundation",
                path: "lib/amazin/foundation/",
                forbidden_prefixes: [
                  "Amazin.Domain",
                  "Amazin.Pages",
                  "Amazin.Actions",
                  "Amazin.UI"
                ]
              }
            ]
          ]},

          # ── 2. Horizontal UI↔Domain machine independence ──────────────
          #
          # CartUI must not reference CartDomain and vice versa.
          # Add more pairs as machines are added (e.g., Order, Wishlist).
          #
          {Credo.Check.Custom.V14HorizontalCoupling, [
            pairs: [
              %{
                name: "Cart",
                ui_path: "lib/amazin/ui/cart_ui",
                ui_forbidden: ["Amazin.Domain.CartDomain"],
                domain_path: "lib/amazin/domain/cart_domain",
                domain_forbidden: ["Amazin.UI."]
              }
            ]
          ]},

          # ── 3. Signal flow direction ──────────────────────────────────
          #
          # Only domain machines emit signal(); only UI machines define react/2.
          #
          {Credo.Check.Custom.V14SignalDiscipline, [
            ui_path: "lib/amazin/ui/",
            domain_path: "lib/amazin/domain/"
          ]},

          # ── 4. Typed outcome constructors ─────────────────────────────
          #
          # Machine modules should use Outcome.flash(...) not {:flash, ...}.
          #
          {Credo.Check.Custom.V14OutcomeConstructor, [
            machine_paths: ["lib/amazin/ui/", "lib/amazin/domain/"],
            outcome_tags: [
              :flash, :redirect, :stream_insert, :stream_delete,
              :stream_reset, :push_event, :persist_quantity,
              :persist_remove, :start_checkout, :signal
            ]
          ]},

          # ── 5. Thin LiveView shell ────────────────────────────────────
          #
          # LiveView should delegate to machines, not call domain services directly.
          #
          {Credo.Check.Custom.V14LiveViewThinShell, [
            liveview_path: "lib/amazin_web/live/",
            forbidden_in_liveview: [
              "Amazin.Domain.Pricing",
              "Amazin.Domain.Checkout"
            ]
          ]}
        ]
      }
    }
  ]
}
