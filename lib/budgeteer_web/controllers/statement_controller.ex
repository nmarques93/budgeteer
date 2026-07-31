defmodule BudgeteerWeb.StatementController do
  use BudgeteerWeb, :controller

  alias Budgeteer.Ledger
  alias Budgeteer.Statements

  # A plain multipart form POST, not a LiveView upload — see CLAUDE.md for
  # why: LiveView's channel-based upload (allow_upload/consume_uploaded_entries)
  # was silently never completing (entries stuck at 0%, Upload button stuck
  # disabled) with no clear root cause. This uses Plug's ordinary multipart
  # parsing instead, which has none of that machinery to fail.
  @max_file_size 15_000_000
  @allowed_extensions ~w(.pdf .jpg .jpeg .png)

  # Extension alone is trivially spoofable (rename anything to .png) — this
  # confirms the file's actual bytes match one of the formats we claim to
  # accept, via the same magic-number signatures browsers/OSes use, before
  # anything gets written to disk or handed to the AI client.
  @magic_bytes %{
    ".pdf" => "%PDF-",
    ".jpg" => <<0xFF, 0xD8, 0xFF>>,
    ".jpeg" => <<0xFF, 0xD8, 0xFF>>,
    ".png" => <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>
  }

  def create(conn, %{"account_id" => account_id} = params) do
    scope = conn.assigns.current_scope
    account = Ledger.get_account!(scope, account_id)

    case params["statement"] do
      %{"file" => %Plug.Upload{} = upload} ->
        handle_upload(conn, scope, account, upload)

      _ ->
        conn
        |> put_flash(:error, gettext("Please select a file to upload"))
        |> redirect(to: ~p"/accounts/#{account}/statements/new")
    end
  end

  defp handle_upload(conn, scope, account, %Plug.Upload{} = upload) do
    ext = upload.filename |> Path.extname() |> String.downcase()

    cond do
      ext not in @allowed_extensions ->
        conn
        |> put_flash(:error, gettext("Unsupported file type — use PDF, JPG, or PNG"))
        |> redirect(to: ~p"/accounts/#{account}/statements/new")

      File.stat!(upload.path).size > @max_file_size ->
        conn
        |> put_flash(:error, gettext("File is too large (max 15 MB)"))
        |> redirect(to: ~p"/accounts/#{account}/statements/new")

      not matches_magic_bytes?(ext, upload.path) ->
        conn
        |> put_flash(
          :error,
          gettext("File content doesn't match its extension — use a real PDF, JPG, or PNG")
        )
        |> redirect(to: ~p"/accounts/#{account}/statements/new")

      true ->
        save_statement(conn, scope, account, upload)
    end
  end

  defp matches_magic_bytes?(ext, path) do
    signature = Map.fetch!(@magic_bytes, ext)
    header = File.open!(path, [:read, :binary], &IO.binread(&1, byte_size(signature)))
    header == signature
  end

  defp save_statement(conn, scope, account, upload) do
    file_bytes = File.read!(upload.path)
    file_hash = :crypto.hash(:sha256, file_bytes) |> Base.encode16(case: :lower)

    storage_dir =
      Path.join(Application.fetch_env!(:budgeteer, :statement_storage_path), account.id)

    File.mkdir_p!(storage_dir)
    storage_path = Path.join(storage_dir, file_hash <> Path.extname(upload.filename))
    # The raw bank statement itself (not just the AI-extracted JSON) is
    # sensitive — encrypted at rest with the same Vault as raw_ai_output,
    # so a compromised disk/volume doesn't expose plaintext statements.
    File.write!(storage_path, Budgeteer.Vault.encrypt!(file_bytes))

    attrs = %{
      "filename" => upload.filename,
      "storage_path" => storage_path,
      "file_hash" => file_hash,
      "account_id" => account.id,
      "uploaded_by_id" => scope.user.id
    }

    case Statements.create_statement(scope, attrs) do
      {:ok, _statement} ->
        conn
        |> put_flash(:info, gettext("Statement uploaded — processing will begin shortly"))
        |> redirect(to: ~p"/accounts/#{account}/statements")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, changeset_error_message(changeset))
        |> redirect(to: ~p"/accounts/#{account}/statements/new")
    end
  end

  defp changeset_error_message(changeset) do
    case changeset.errors[:file_hash] do
      {_msg, _opts} = error ->
        gettext("File %{message}", message: BudgeteerWeb.CoreComponents.translate_error(error))

      nil ->
        gettext("Could not save statement")
    end
  end
end
