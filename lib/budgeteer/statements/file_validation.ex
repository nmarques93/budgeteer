defmodule Budgeteer.Statements.FileValidation do
  @moduledoc """
  Shared upload validation for bank statement files — extension whitelist
  plus magic-byte sniffing (extension alone is trivially spoofable by
  renaming any file) — used by both the manual-upload path
  (`StatementController`) and inbound-email attachments
  (`InboundEmailController`). Lives in `Statements`, not `_web`, since
  neither caller does anything controller-specific here.
  """

  @max_file_size 15_000_000
  @allowed_extensions ~w(.pdf .jpg .jpeg .png)

  @magic_bytes %{
    ".pdf" => "%PDF-",
    ".jpg" => <<0xFF, 0xD8, 0xFF>>,
    ".jpeg" => <<0xFF, 0xD8, 0xFF>>,
    ".png" => <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>
  }

  def max_file_size, do: @max_file_size

  def allowed_extension?(ext), do: ext in @allowed_extensions

  @doc """
  Checks the file's actual bytes match the claimed extension's magic
  number. `header_bytes` only needs to be as long as the longest known
  signature — callers with a file on disk can read just that much rather
  than loading the whole file.
  """
  def matches_magic_bytes?(ext, header_bytes) when is_binary(header_bytes) do
    case Map.fetch(@magic_bytes, ext) do
      {:ok, signature} ->
        size = min(byte_size(signature), byte_size(header_bytes))
        :binary.part(header_bytes, 0, size) == signature

      :error ->
        false
    end
  end
end
