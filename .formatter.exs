[
  inputs: [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "mix.exs"
  ],
  locals_without_parens: [allow: :*, expect: :*],
  export: [
    locals_without_parens: [allow: :*, expect: :*]
  ]
]
