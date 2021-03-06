defmodule Phoenix.HTML.Engine do
  @moduledoc """
  This is an implementation of EEx.Engine that guarantees
  templates are HTML Safe.
  """

  use EEx.Engine

  @doc false
  def handle_body(body), do: body

  @doc false
  def handle_text(buffer, text) do
    quote do
      {:safe, [unquote(unwrap(buffer))|unquote(text)]}
    end
  end

  @doc false
  def handle_expr(buffer, "=", expr) do
    line   = line_from_expr(expr)
    expr   = expr(expr)
    buffer = unwrap(buffer)
    {:safe, quote do
      tmp1 = unquote(buffer)
      [tmp1|unquote(to_safe(expr, line))]
     end}
  end

  @doc false
  def handle_expr(buffer, "", expr) do
    expr   = expr(expr)
    buffer = unwrap(buffer)

    quote do
      tmp2 = unquote(buffer)
      unquote(expr)
      tmp2
    end
  end

  defp line_from_expr({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line)
  defp line_from_expr(_), do: nil

  # We can do the work at compile time
  defp to_safe(literal, _line) when is_binary(literal) or is_atom(literal) or is_number(literal) do
    Phoenix.HTML.Safe.to_iodata(literal)
  end

  # We can do the work at runtime
  defp to_safe(literal, line) when is_list(literal) do
    quote line: line, do: Phoenix.HTML.Safe.to_iodata(unquote(literal))
  end

  # We need to check at runtime and we do so by
  # optimizing common cases.
  defp to_safe(expr, line) do
    # Keep stacktraces for protocol dispatch...
    fallback = quote line: line, do: Phoenix.HTML.Safe.to_iodata(other)

    # However ignore them for the generated clauses to avoid warnings
    quote line: -1 do
      case unquote(expr) do
        {:safe, data} -> data
        bin when is_binary(bin) -> Plug.HTML.html_escape(bin)
        other -> unquote(fallback)
      end
    end
  end

  defp expr(expr) do
    Macro.prewalk(expr, &EEx.Engine.handle_assign/1)
  end

  defp unwrap({:safe, value}), do: value
  defp unwrap(value), do: value
end
