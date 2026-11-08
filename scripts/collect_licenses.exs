# Run in the builder after fetching dependencies; no application startup required.
[dependencies, destination] = System.argv()
File.mkdir_p!(destination)

copy = fn source, relative ->
  target = Path.join(destination, relative)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(source, target)
end

license_file? = fn path ->
  File.regular?(path) and
    Regex.match?(~r/^(licen[cs]e|copying|copyright|notice)([.\-_].*)?$/i, Path.basename(path))
end

dependencies
|> Path.join("**/*")
|> Path.wildcard()
|> Enum.filter(license_file?)
|> Enum.each(fn path -> copy.(path, "dependencies/" <> Path.relative_to(path, dependencies)) end)

for {name, root} <- [
      {"erlang", :code.root_dir() |> List.to_string()},
      {"elixir", Application.app_dir(:elixir) |> Path.dirname() |> Path.dirname()}
    ],
    path <- Path.wildcard(Path.join(root, "**/*")),
    license_file?.(path) do
  copy.(path, "runtime/#{name}/" <> Path.relative_to(path, root))
end

# Preserve the existing bundled source/header without maintaining a duplicate notice.
if File.regular?("assets/vendor/topbar.js"),
  do: copy.("assets/vendor/topbar.js", "vendor/topbar.js")
