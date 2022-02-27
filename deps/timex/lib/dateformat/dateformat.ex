defmodule Timex.DateFormat do
  @moduledoc """
  Date formatting and parsing.

  This module provides an interface and core implementation for converting date
  values into strings (formatting) or the other way around (parsing) according
  to the specified template.

  Multiple template formats are supported, each one provided by a separate
  module. One can also implement custom formatters for use with this module.
  """
  alias Timex.DateTime
  alias Timex.DateFormat.Formatters.Formatter
  alias Timex.DateFormat.Formatters.StrftimeFormatter
  alias Timex.Parsers.DateFormat.Parser
  alias Timex.Parsers.DateFormat.StrftimeParser

  @doc """
  Converts date values to strings according to the given template (aka format string).
  """
  @spec format(%DateTime{}, String.t) :: {:ok, String.t} | {:error, String.t}
  defdelegate format(%DateTime{} = date, format_string), to: Formatter

  @doc """
  Same as `format/2`, but takes a custom formatter.
  """
  @spec format(%DateTime{}, String.t, atom) :: {:ok, String.t} | {:error, String.t}
  def format(%DateTime{} = date, format_string, :default),
    do: Formatter.format(date, format_string)
  def format(%DateTime{} = date, format_string, :strftime),
    do: Formatter.format(date, format_string, StrftimeFormatter)
  defdelegate format(%DateTime{} = date, format_string, formatter), to: Formatter

  @doc """
  Raising version of `format/2`. Returns a string with formatted date or raises a `FormatError`.
  """
  @spec format!(%DateTime{}, String.t) :: String.t | no_return
  defdelegate format!(%DateTime{} = date, format_string), to: Formatter

  @doc """
  Raising version of `format/3`. Returns a string with formatted date or raises a `FormatError`.
  """
  @spec format!(%DateTime{}, String.t, atom) :: String.t | no_return
  def format!(%DateTime{} = date, format_string, :default),
    do: Formatter.format!(date, format_string)
  def format!(%DateTime{} = date, format_string, :strftime),
    do: Formatter.format!(date, format_string, StrftimeFormatter)
  defdelegate format!(%DateTime{} = date, format_string, formatter), to: Formatter

  @doc """
  Parses the date encoded in `string` according to the template.
  """
  @spec parse(String.t, String.t) :: {:ok, %DateTime{}} | {:error, term}
  defdelegate parse(date_string, format_string), to: Parser

  @doc """
  Parses the date encoded in `string` according to the template by using the
  provided formatter.
  """
  @spec parse(String.t, String.t, atom) :: {:ok, %DateTime{}} | {:error, term}
  def parse(date_string, format_string, :default),  do: Parser.parse(date_string, format_string)
  def parse(date_string, format_string, :strftime), do: Parser.parse(date_string, format_string, StrftimeParser)
  defdelegate parse(date_string, format_string, parser), to: Parser

  @doc """
  Raising version of `parse/2`. Returns a DateTime struct, or raises a `ParseError`.
  """
  @spec parse!(String.t, String.t) :: %DateTime{} | no_return
  defdelegate parse!(date_string, format_string), to: Parser

  @doc """
  Raising version of `parse/3`. Returns a DateTime struct, or raises a `ParseError`.
  """
  @spec parse!(String.t, String.t, atom) :: %DateTime{} | no_return
  def parse!(date_string, format_string, :default),  do: Parser.parse!(date_string, format_string)
  def parse!(date_string, format_string, :strftime), do: Parser.parse!(date_string, format_string, StrftimeParser)
  defdelegate parse!(date_string, format_string, parser), to: Parser

  @doc """
  Verifies the validity of the given format string. The default formatter is assumed.

  Returns `:ok` if the format string is clean, `{ :error, <reason> }` otherwise.
  """
  @spec validate(String.t) :: :ok | {:error, term}
  defdelegate validate(format_string), to: Formatter

  @doc """
  Verifies the validity of the given format string according to the provided
  formatter.

  Returns `:ok` if the format string is clean, `{ :error, <reason> }` otherwise.
  """
  @spec validate(String.t, atom) :: :ok | {:error, term}
  def validate(format_string, :default),  do: Formatter.validate(format_string)
  def validate(format_string, :strftime), do: Formatter.validate(format_string, StrftimeFormatter)
  defdelegate validate(format_string, formatter), to: Formatter
end
