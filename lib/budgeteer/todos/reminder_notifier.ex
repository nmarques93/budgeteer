defmodule Budgeteer.Todos.ReminderNotifier do
  use Gettext, backend: BudgeteerWeb.Gettext

  import Swoosh.Email

  alias Budgeteer.Mailer
  alias Budgeteer.Todos.TodoItem

  def deliver_todo_reminder(recipient_email, recipient_locale, %TodoItem{} = item) do
    Gettext.with_locale(BudgeteerWeb.Gettext, recipient_locale || "en", fn ->
      email =
        new()
        |> to(recipient_email)
        |> from(Application.fetch_env!(:budgeteer, :mail_from))
        |> subject(gettext("TODO reminder: %{title}", title: item.title))
        |> text_body(body(item))

      case Mailer.deliver(email) do
        {:ok, _metadata} -> {:ok, email}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp body(%TodoItem{due_date: due_date, todo_list: todo_list} = item) do
    due_text =
      case Date.compare(due_date, Date.utc_today()) do
        :lt -> gettext("This task is overdue since %{date}.", date: due_date)
        :eq -> gettext("This task is due today.")
        :gt -> gettext("This task is due on %{date}.", date: due_date)
      end

    """

    #{gettext("You have a TODO reminder:")}

    #{item.title}
    #{gettext("List: %{name}", name: todo_list.name)}
    #{due_text}
    """
  end
end
