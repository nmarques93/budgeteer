defmodule Budgeteer.Statements.ParseWorker do
  @moduledoc """
  Oban worker that reads an uploaded statement file, calls the AI client to
  extract transactions, and stores the result on the `Statement` record.
  Never creates `Transaction` records itself — see `Budgeteer.Statements`.
  """

  use Oban.Worker, queue: :statements, max_attempts: 3

  alias Budgeteer.Ledger
  alias Budgeteer.Statements

  @impl true
  def perform(%Oban.Job{args: %{"statement_id" => statement_id}} = job) do
    statement = Statements.get_statement!(statement_id)

    with {:ok, processing_statement} <- Statements.mark_processing(statement),
         category_names <- Ledger.list_category_names(processing_statement.household_id),
         {:ok, encrypted_bytes} <- File.read(processing_statement.storage_path),
         {:ok, file_bytes} <- Budgeteer.Vault.decrypt(encrypted_bytes),
         media_type <- media_type(processing_statement.filename),
         {:ok, parsed} <- ai_client().parse_statement(file_bytes, media_type, category_names),
         {:ok, _processed_statement} <- Statements.mark_processed(processing_statement, parsed) do
      :ok
    else
      {:error, reason} ->
        # Only give up (mark :failed) on the last scheduled attempt — a
        # transient blip (a flaky AI response, a network hiccup) gets
        # Oban's normal retry-with-backoff instead of failing the statement
        # on the very first hiccup. The statement stays :processing across
        # retries, matching the existing "still working on it" UI banner.
        if job.attempt >= job.max_attempts do
          Statements.mark_failed(statement, format_error(reason))
        end

        {:error, reason}
    end
  end

  defp ai_client, do: Application.get_env(:budgeteer, :ai_client, Budgeteer.AI.Client)

  defp media_type(filename) do
    case filename |> Path.extname() |> String.downcase() do
      ".pdf" -> "application/pdf"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      _ -> "application/octet-stream"
    end
  end

  defp format_error(reason), do: inspect(reason)
end
