defmodule BudgeteerWeb.StatementLive.Upload do
  use BudgeteerWeb, :live_view

  alias Budgeteer.Ledger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} online_members={@online_members}>
      <.header>
        {gettext("Upload statement")}
        <:subtitle>{gettext("For %{account}", account: @account.name)}</:subtitle>
      </.header>

      <div
        id="native-camera-upload"
        phx-hook=".NativeCameraUpload"
        data-action={~p"/accounts/#{@account}/statements"}
        data-error-camera={gettext("Could not take a photo — please try again.")}
        data-error-upload={gettext("Upload failed — please try again.")}
        class="hidden rounded-box border border-base-300 p-6 mb-4"
      >
        <button type="button" data-take-photo class="btn btn-primary w-full">
          <.icon name="hero-camera" /> {gettext("Take a photo")}
        </button>
        <p data-status class="text-sm text-error mt-2"></p>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".NativeCameraUpload">
          export default {
            mounted() {
              if (!window.Capacitor?.isNativePlatform?.()) return
              this.el.classList.remove("hidden")

              this.button = this.el.querySelector("[data-take-photo]")
              this.onClick = () => this.takePhoto()
              this.button.addEventListener("click", this.onClick)
            },

            destroyed() {
              this.button?.removeEventListener("click", this.onClick)
            },

            async takePhoto() {
              const { Camera } = window.Capacitor.Plugins
              this.button.disabled = true
              this.setStatus("")

              try {
                const photo = await Camera.takePhoto({ quality: 90, saveToGallery: false })
                const blob = await (await fetch(photo.webPath)).blob()
                const extension = (photo.format || "jpeg").replace("jpg", "jpeg")

                const formData = new FormData()
                formData.append("statement[file]", blob, `statement.${extension}`)

                const csrfToken = document.querySelector('meta[name="csrf-token"]').content
                const response = await fetch(this.el.dataset.action, {
                  method: "POST",
                  headers: { "x-csrf-token": csrfToken },
                  body: formData
                })

                if (response.ok) {
                  window.location.href = response.url
                } else {
                  this.setStatus(this.el.dataset.errorUpload)
                }
              } catch (error) {
                if (error?.message !== "User cancelled photos app") {
                  this.setStatus(this.el.dataset.errorCamera)
                }
              } finally {
                this.button.disabled = false
              }
            },

            setStatus(text) {
              const status = this.el.querySelector("[data-status]")
              if (status) status.textContent = text
            }
          }
        </script>
      </div>

      <.form for={%{}} action={~p"/accounts/#{@account}/statements"} method="post" multipart>
        <div class="rounded-box border border-base-300 p-6">
          <input
            type="file"
            name="statement[file]"
            accept=".pdf,.jpg,.jpeg,.png"
            required
            class="w-full"
          />
          <p class="text-sm opacity-70 mt-2">{gettext("PDF, JPG, or PNG — up to 15 MB.")}</p>
        </div>

        <footer class="mt-4">
          <.button phx-disable-with={gettext("Uploading...")} variant="primary">
            {gettext("Upload")}
          </.button>
          <.button navigate={~p"/accounts/#{@account}/statements"}>{gettext("Cancel")}</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"account_id" => account_id}, _session, socket) do
    account = Ledger.get_account!(socket.assigns.current_scope, account_id)

    {:ok,
     socket
     |> assign(:page_title, gettext("Upload Statement"))
     |> assign(:account, account)}
  end
end
