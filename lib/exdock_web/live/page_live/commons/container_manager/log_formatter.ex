defmodule ExdockWeb.Commons.ContainerManager.LogFormatter do
  @moduledoc false

  @styles %{
    1 => "font-weight:bold",
    2 => "opacity:0.5",
    3 => "font-style:italic",
    4 => "text-decoration:underline",
    5 => "text-decoration:blink",
    7 => "filter:invert(100%)",
    8 => "visibility:hidden",
    9 => "text-decoration:line-through",
    30 => "color:black",
    31 => "color:red",
    32 => "color:green",
    33 => "color:yellow",
    34 => "color:blue",
    35 => "color:magenta",
    36 => "color:turquoise",
    37 => "color:white",
    40 => "background-color:black",
    41 => "background-color:red",
    42 => "background-color:green",
    43 => "background-color:yellow",
    44 => "background-color:blue",
    45 => "background-color:magenta",
    46 => "background-color:turquoise",
    47 => "background-color:white",
    90 => "color:gray",
    91 => "color:red",
    92 => "color:green",
    93 => "color:yellow",
    94 => "color:blue",
    95 => "color:magenta",
    96 => "color:turquoise",
    97 => "color:white",
    100 => "background-color:gray",
    101 => "background-color:red",
    102 => "background-color:green",
    103 => "background-color:yellow",
    104 => "background-color:blue",
    105 => "background-color:magenta",
    106 => "background-color:turquoise",
    107 => "background-color:white"
  }

  @spec format(String.t()) :: Phoenix.HTML.safe()
  def format(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> replace_ansi_codes()
    |> Phoenix.HTML.raw()
  end

  defp replace_ansi_codes(escaped_text) do
    Regex.replace(~r/\e\[(\d+)m/, escaped_text, fn _match, code ->
      code
      |> String.to_integer()
      |> ansi_markup()
    end)
  end

  defp ansi_markup(0), do: "</span>"

  defp ansi_markup(code) do
    case Map.fetch(@styles, code) do
      {:ok, style} -> "<span style=\"#{style}\">"
      :error -> ""
    end
  end
end
