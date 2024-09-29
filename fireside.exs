defmodule Amazin.FiresideConfig do
  def config do
    [
      name: :amazin,
      version: 1,
      files: [
        required: [
          "lib/amazin/context.ex",
          "lib/amazin/context/**/*.{ex,exs}",
          "test/amazin/**/*_test.{ex,exs}"
        ],
        optional: [
          "lib/amazin_web/endpoint.ex"
        ]
      ]
    ]
  end
end
