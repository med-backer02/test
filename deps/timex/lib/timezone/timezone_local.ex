defmodule Timex.Timezone.Local do
  @moduledoc """
  Contains the logic and parser for extracting local timezone configuration.
  """
  alias Timex.DateTime,              as: DateTime
  alias Timex.Date,                  as: Date
  alias Timex.Timezone.Database,     as: ZoneDatabase
  alias Timex.Parsers.ZoneInfo,      as: ZoneParser
  alias Timex.Parsers.ZoneInfo.TransitionInfo

  @_ETC_TIMEZONE      "/etc/timezone"
  @_ETC_SYS_CLOCK     "/etc/sysconfig/clock"
  @_ETC_CONF_CLOCK    "/etc/conf.d/clock"
  @_ETC_LOCALTIME     "/etc/localtime"
  @_USR_ETC_LOCALTIME "/usr/local/etc/localtime"

  @doc """
  Looks up the local timezone configuration. Returns the name of a timezone
  in the Olson database.
  """
  @spec lookup(DateTime.t | nil) :: String.t

  def lookup(), do: Date.universal |> lookup
  def lookup(date) do
    case :os.type() do
      {:unix, :darwin} -> localtz(:osx, date)
      {:unix, _}       -> localtz(:unix, date)
      {:nt}            -> localtz(:win, date)
      _                -> raise "Unsupported operating system!"
    end
  end

  # Get the locally configured timezone on OSX systems
  defp localtz(:osx, date) do
    # Allow TZ environment variable to override lookup
    case System.get_env("TZ") do
      nil ->
        # Most accurate local timezone will come from /etc/localtime,
        # since we can lookup proper timezones for arbitrary dates
        case read_timezone_data(nil, @_ETC_LOCALTIME, date) do
          {:ok, tz} -> tz
          _ ->
            # Fallback and ask systemsetup
            tz = System.cmd("systemsetup", "-gettimezone")
            |> IO.iodata_to_binary
            |> String.strip(?\n)
            |> String.replace("Time Zone: ", "")
            if String.length(tz) > 0 do
              tz
            else
              raise("Unable to find local timezone.")
            end
        end
      tz -> tz
    end
  end

  # Get the locally configured timezone on *NIX systems
  defp localtz(:unix, date) do
    case System.get_env("TZ") do
      # Not found
      nil ->
        # Since that failed, check distro specific config files
        # containing the timezone name. To clean up the code here
        # we're using pipes, even though we may find the value we
        # are looking for on the first try. The way the function
        # defs are set up, if we find a value, it's just passed
        # along through the pipe until we're done. If we don't,
        # this will try each fallback location in order.
        {:ok, tz} = read_timezone_data(@_ETC_TIMEZONE, date)
        |> read_timezone_data(@_ETC_SYS_CLOCK, date)
        |> read_timezone_data(@_ETC_CONF_CLOCK, date)
        |> read_timezone_data(@_ETC_LOCALTIME, date)
        |> read_timezone_data(@_USR_ETC_LOCALTIME, date)
        tz
      tz  -> tz
    end
  end

  # Get the locally configured timezone on Windows systems
  @local_tz_key 'SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation'
  @sys_tz_key   'SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Time Zones'
  # We ignore the reference date here, since there is no way to lookup
  # transition times for historical/future dates
  defp localtz(:win, _date) do
    # Windows has many of it's own unique time zone names, which can
    # also be translated to the OS's language.
    {:ok, handle} = :win32reg.open(:local_machine)
    :ok           = :win32reg.change_key(handle, @local_tz_key)
    {:ok, values} = :win32reg.values(handle)
    if List.keymember?(values, 'TimeZoneKeyName', 0) do
      # Windows 7/Vista
      # On some systems the string value might be padded with excessive \0 bytes, trim them
      List.keyfind(values, 'TimeZoneKeyName', 0)
      |> IO.iodata_to_binary
      |> String.strip ?\0
    else
      # Windows 2000 or XP
      # This is the localized name:
      localized = List.keyfind(values, 'StandardName', 0)
      # Open the list of timezones to look up the real name:
      :ok            = :win32reg.change_key(handle, @sys_tz_key)
      {:ok, subkeys} = :win32reg.sub_keys(handle)
      # Iterate over each subkey (timezone), and match against the localized name
      tzone = Enum.find subkeys, fn subkey ->
        :ok           = :win32reg.change_key(handle, subkey)
        {:ok, values} = :win32reg.values(handle)
        case List.keyfind(values, 'Std', 0) do
          {_, zone} when zone == localized -> zone
          _ -> nil
        end
      end
      # If we don't have a timezone yet, we've failed,
      # Otherwise, we need to lookup the final timezone name
      # in the dictionary of unique Windows timezone names
      cond do
        tzone == nil -> raise "Could not find Windows time zone configuration!"
        tzone -> 
          timezone = tzone |> IO.iodata_to_binary
          case ZoneDatabase.to_olson(timezone) do
            nil ->
              # Try appending "Standard Time"
              case ZoneDatabase.to_olson("#{timezone} Standard Time") do
                nil   -> raise "Could not find Windows time zone configuration!"
                final -> final
              end
            final -> final
          end
      end
    end
  end

  # Attempt to read timezone data from /etc/timezone
  defp read_timezone_data(@_ETC_TIMEZONE, date) do
    case File.exists?(@_ETC_TIMEZONE) do
      true ->
        etctz = File.read!(@_ETC_TIMEZONE)
        case etctz |> String.starts_with?("TZif2") do
          true ->
            case etctz |> parse_tzfile(date) do
              {:ok, tz}   -> {:ok, tz}
              {:error, m} -> raise m
            end
          false ->
            [no_hostdefs | _] = etctz |> String.split " ", [global: false, trim: true]
            [no_comments | _] = no_hostdefs |> String.split "#", [global: false, trim: true]
            {:ok, no_comments |> String.replace(" ", "_") |> String.strip(?\n)}
        end
      _ ->
        nil
    end
  end
  # If we've found a timezone, just keep on piping it through
  defp read_timezone_data({:ok, _} = result, _, _date), do: result
  # Otherwise, read the next fallback location
  defp read_timezone_data(_, file, _date) when file == @_ETC_SYS_CLOCK or file == @_ETC_CONF_CLOCK do
    case File.exists?(file) do
      true ->
        match = file
        |> File.stream!
        |> Stream.filter(fn line -> Regex.match?(~r/(^ZONE=)|(^TIMEZONE=)/, line) end)
        |> Enum.to_list
        |> List.first
        case match do
          m when m != nil ->
            [_, tz, _] = m |> String.split "\""
            {:ok, tz |> String.replace " ", "_"}
          _ ->
            nil
        end
      _ ->
        nil
    end
  end
  defp read_timezone_data(_, file, date) when file == @_ETC_LOCALTIME or file == @_USR_ETC_LOCALTIME do
    case File.exists?(file) do
      true ->
        case file |> File.read! |> parse_tzfile(date) do
          {:ok, tz}   -> {:ok, tz}
          {:error, m} -> raise m
        end
      _ ->
        nil
    end
  end

  @doc """
  Given a binary representing the data from a tzfile (not the source version),
  parses out the timezone for the provided reference date, or current UTC time
  if one wasn't provided.
  """
  @spec parse_tzfile(binary, DateTime.t | nil) :: {:ok, String.t} | {:error, term}

  def parse_tzfile(tzdata), do: parse_tzfile(tzdata, Date.universal())
  def parse_tzfile(tzdata, %DateTime{} = reference_date) when tzdata != nil do
    # Parse file to Zone{}
    {:ok, zone} = ZoneParser.parse(tzdata)
    # Get the zone for the current time
    timestamp  = reference_date |> Date.to_secs
    transition = zone.transitions
      |> Enum.sort(fn %TransitionInfo{starts_at: utime1}, %TransitionInfo{starts_at: utime2} -> utime1 > utime2 end)
      |> Enum.reject(fn %TransitionInfo{starts_at: unix_time} -> unix_time > timestamp end)
      |> List.first
    # We'll need these handy
    # Attempt to get the proper timezone for the current transition we're in
    result = cond do
      # Success
      transition != nil -> {:ok, transition.abbreviation}
      # Fallback to the first standard-time zone available
      true ->
        fallback = zone.transitions
          |> Enum.filter(fn zone -> zone.is_std? end)
          |> List.last
        case fallback do
          # Well, there are no standard-time zones then, just take the first zone available
          nil  -> 
            last_transition = zone.transitions |> List.last
            {:ok, last_transition.abbreviation}
          # Found a reasonable fallback zone, success?
          %TransitionInfo{abbreviation: abbreviation} ->
            {:ok, abbreviation}
        end
    end
    result || {:error, "Unable to locate the current timezone!"}
  end
end
