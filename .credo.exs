%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [],
      requires: ["lib/amazin/credo/ala_layer_boundary.ex"],
      strict: false,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # --- ALA layer boundary enforcement ---
          #
          # Domain modules are pure — no persistence, no Phoenix, no framework.
          # Pages are pure state machines — no I/O, no Phoenix.
          # Foundation handles persistence/I/O — no upward deps into Domain/Pages.
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
                  "AmazinWeb",
                  "Phoenix",
                  "Ecto.Repo",
                  "Ecto.Query",
                  "Ecto.Changeset"
                ]
              },
              %{
                name: "Pages",
                path: "lib/amazin/pages/",
                forbidden_prefixes: [
                  "Amazin.Foundation",
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
                  "Amazin.Actions"
                ]
              }
            ]
          ]}
        ]
      }
    }
  ]
}
